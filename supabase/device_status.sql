-- ─────────────────────────────────────────────────────────────────────
--  HarBest: device connection status ("heartbeat")
--
--  Run this once in the Supabase dashboard → SQL Editor → New query.
--  Safe to run again: everything uses IF NOT EXISTS / OR REPLACE.
--
--  The Raspberry Pi calls device_heartbeat() every 30 seconds. The app
--  reads device_status to show Online / Delayed / Offline and the health
--  of each sensor (DHT22, NPK, camera).
-- ─────────────────────────────────────────────────────────────────────

-- 1) One row per device, overwritten on every heartbeat.
create table if not exists public.device_status (
  device_id     text primary key,
  last_seen     timestamptz not null default now(),  -- real UTC, set by the server
  dht22_ok      boolean,
  npk_ok        boolean,
  camera_ok     boolean,
  mqtt_ok       boolean,
  wifi_rssi     integer,        -- dBm, e.g. -55 (closer to 0 = stronger)
  ip_address    text,
  uptime_s      bigint,         -- seconds since the Pi booted
  cpu_temp      real,           -- °C
  last_read_at  text,           -- Pi's local clock time of its last sensor cycle
  software      text            -- script version string
);

-- 2) Only signed-in users can read, and only the devices behind crops
--    they can already see (the sub-select obeys the crops table's own RLS,
--    so an admin who sees every crop sees every device).
alter table public.device_status enable row level security;

drop policy if exists "read status of visible devices" on public.device_status;
create policy "read status of visible devices"
  on public.device_status
  for select
  to authenticated
  using (device_id in (select c.device_id from public.crops c));

-- 3) The Pi writes through this function, never through the table directly.
--    SECURITY DEFINER lets it upsert even though the table has no insert
--    policy. It only accepts device_ids that exist in public.devices.
create or replace function public.device_heartbeat(
  p_device_id text,
  p_status    jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.devices d where d.device_id = p_device_id) then
    raise exception 'Unknown device %', p_device_id using errcode = '22023';
  end if;

  insert into public.device_status as s (
    device_id, last_seen, dht22_ok, npk_ok, camera_ok, mqtt_ok,
    wifi_rssi, ip_address, uptime_s, cpu_temp, last_read_at, software
  ) values (
    p_device_id,
    now(),
    (p_status->>'dht22_ok')::boolean,
    (p_status->>'npk_ok')::boolean,
    (p_status->>'camera_ok')::boolean,
    (p_status->>'mqtt_ok')::boolean,
    (p_status->>'wifi_rssi')::integer,
    p_status->>'ip_address',
    (p_status->>'uptime_s')::bigint,
    (p_status->>'cpu_temp')::real,
    p_status->>'last_read_at',
    p_status->>'software'
  )
  on conflict (device_id) do update set
    last_seen    = excluded.last_seen,
    dht22_ok     = excluded.dht22_ok,
    npk_ok       = excluded.npk_ok,
    camera_ok    = excluded.camera_ok,
    mqtt_ok      = excluded.mqtt_ok,
    wifi_rssi    = excluded.wifi_rssi,
    ip_address   = excluded.ip_address,
    uptime_s     = excluded.uptime_s,
    cpu_temp     = excluded.cpu_temp,
    last_read_at = excluded.last_read_at,
    software     = excluded.software;
end;
$$;

revoke all on function public.device_heartbeat(text, jsonb) from public;
grant execute on function public.device_heartbeat(text, jsonb) to anon, authenticated;

-- 4) Push changes to the app instantly (Realtime).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'device_status'
  ) then
    alter publication supabase_realtime add table public.device_status;
  end if;
end $$;
