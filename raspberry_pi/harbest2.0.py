

import time
import json
import os
import base64
import socket
import threading
import urllib.request
import urllib.error
from datetime import datetime

import pigpio
import DHT22
import minimalmodbus
import paho.mqtt.client as mqtt
from picamera2 import Picamera2
from libcamera import controls

# -----------------------------------------------------------------
#  CONFIGURATION
# -----------------------------------------------------------------
MQTT_BROKER = "localhost"
MQTT_PORT = 1883
MQTT_TOPIC_DATA = "harbest/sensor/area1"
MQTT_TOPIC_IMAGE = "harbest/sensor/camera"
CLIENT_ID = "harbest_pi_zero_w"
READ_INTERVAL = 90
CAMERA_INTERVAL = 30

IMAGE_PATH = "/home/pizero/capture.jpg"

IMAGE_WIDTH = 1280
IMAGE_HEIGHT = 720


TEMP_MIN = 15.0
TEMP_MAX = 25.0
HUMID_MIN = 60.0
HUMID_MAX = 80.0
N_MIN = 30
P_MIN = 20
K_MIN = 20  # FIX: was referenced in evaluate_nutrients() but never defined

DHT_MAX_RETRY = 5
DHT_RETRY_DELAY = 2.0
NPK_MAX_RETRY = 3
NPK_RETRY_DELAY = 2.0

# -----------------------------------------------------------------
#  DEVICE STATUS / HEARTBEAT (shown as Online / Offline in the app)
# -----------------------------------------------------------------
# Every HEARTBEAT_INTERVAL seconds the Pi tells Supabase "I'm alive",
# plus whether each sensor worked on the last cycle. It goes straight to
# Supabase over HTTPS, so the app can still see the device even if the
# MQTT -> Supabase forwarding stops.
#
# Set these two values (Supabase dashboard -> Project Settings -> API):
#   SUPABASE_URL      e.g. https://abcdxyz.supabase.co
#   SUPABASE_ANON_KEY the "anon" / "publishable" key (NOT the service_role key)
# Either edit them below or export them as environment variables.
# If they are empty the heartbeat is simply skipped.
SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "")
HEARTBEAT_INTERVAL = 30
SOFTWARE_VERSION = "harbest2.0-heartbeat1"

# Updated by the main loop after every sensor cycle; read by the
# heartbeat thread. None = not measured yet.
last_dht_ok = None
last_npk_ok = None
last_read_at = None

# -----------------------------------------------------------------
#  DHT22 SETUP (GPIO17 = Physical Pin 11)
# -----------------------------------------------------------------
print("[DHT22] Initializing...")
time.sleep(3)


pi = pigpio.pi()
if not pi.connected:
    raise RuntimeError("Could not connect to pigpio daemon. Run 'sudo pigpiod' first.")


GPIO_PIN = 27
sensor = DHT22.sensor(pi, GPIO_PIN)
print("[DHT22] Ready")

last_good_temp = None
last_good_humid = None


# -----------------------------------------------------------------
#  NPK SETUP
# -----------------------------------------------------------------
print("[NPK] Initializing...")
try:
    npk_sensor = minimalmodbus.Instrument('/dev/serial0', 1)
    npk_sensor.serial.baudrate = 4800
    npk_sensor.serial.bytesize = 8
    npk_sensor.serial.parity = minimalmodbus.serial.PARITY_NONE
    npk_sensor.serial.stopbits = 1
    npk_sensor.serial.timeout = 1
    print("[NPK] Ready")
except Exception as e:
    print(f"[NPK] Init failed: {e}")
    npk_sensor = None


# -----------------------------------------------------------------
#  CAMERA (picamera2 -- replaces the old rpicam-jpeg subprocess calls)
# -----------------------------------------------------------------
picam2 = None


def check_camera():
    """Initializes picamera2 once at startup rather than spawning a new
    rpicam-jpeg process on every capture -- keeps a single configured
    camera session alive, which is also what makes autofocus below
    actually persist between shots. Returns True if the camera is
    ready to use."""
    global picam2
    try:
        picam2 = Picamera2()
        config = picam2.create_still_configuration(
            main={"size": (IMAGE_WIDTH, IMAGE_HEIGHT)}
        )
        picam2.configure(config)
        picam2.start()

        try:
            picam2.set_controls({"AfMode": controls.AfModeEnum.Continuous})
        except Exception:
            print("[Camera] Autofocus not supported by this camera module - skipping")

        time.sleep(2)
        print(f"[Camera] picamera2 ready at {IMAGE_WIDTH}x{IMAGE_HEIGHT}")
        return True
    except Exception as e:
        print(f"[Camera] Failed to initialize picamera2: {e}")
        print("[Camera] Make sure it's installed: sudo apt install -y python3-picamera2")
        return False


camera_available = check_camera()

# -----------------------------------------------------------------
#  MQTT SETUP
# -----------------------------------------------------------------
def on_connect(client, userdata, flags, rc, properties):
    status = {
        0: "Connected", 1: "Wrong protocol",
        2: "Invalid ID", 3: "Unavailable",
        4: "Bad credentials", 5: "Not authorized"
    }
    print(f"[MQTT] {status.get(rc.value, f'Code {rc}')}")


def on_disconnect(client, userdata, flags, reason_code, properties):
    print("[MQTT] Disconnected. Reconnecting...")
    while True:
        try:
            client.reconnect()
            print("[MQTT] Reconnected")
            break
        except Exception:
            print("[MQTT] Retry in 5s...")
            time.sleep(5)


def on_publish(client, userdata, mid, rc, properties):
    print("[MQTT] Published")


client = mqtt.Client(
    mqtt.CallbackAPIVersion.VERSION2,
    client_id=CLIENT_ID,
    clean_session=True
)
client.on_connect = on_connect
client.on_disconnect = on_disconnect
client.on_publish = on_publish
print(f"[MQTT] Connecting to {MQTT_BROKER}:{MQTT_PORT}...")
client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
client.loop_start()


# -----------------------------------------------------------------
#  HEARTBEAT
# -----------------------------------------------------------------
heartbeat_stop = threading.Event()
heartbeat_wake = threading.Event()


def _read_wifi_rssi():
    """Signal level of wlan0 in dBm (e.g. -55), or None."""
    try:
        with open("/proc/net/wireless") as f:
            for line in f:
                if line.strip().startswith("wlan0:"):
                    # wlan0: 0000   54.  -56.  -256  ...
                    level = line.split()[3].rstrip(".")
                    return int(float(level))
    except Exception:
        pass
    return None


def _read_cpu_temp():
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            return round(int(f.read().strip()) / 1000.0, 1)
    except Exception:
        return None


def _read_uptime():
    try:
        with open("/proc/uptime") as f:
            return int(float(f.read().split()[0]))
    except Exception:
        return None


def _read_ip():
    """Local IP used to reach the internet (no packet is actually sent)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return None
    finally:
        s.close()


def send_heartbeat():
    """One heartbeat to Supabase. Returns True on success. Never raises."""
    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        return False
    body = {
        "p_device_id": CLIENT_ID,
        "p_status": {
            "dht22_ok": last_dht_ok,
            "npk_ok": last_npk_ok,
            "camera_ok": camera_available,
            "mqtt_ok": client.is_connected(),
            "wifi_rssi": _read_wifi_rssi(),
            "ip_address": _read_ip(),
            "uptime_s": _read_uptime(),
            "cpu_temp": _read_cpu_temp(),
            "last_read_at": last_read_at,
            "software": SOFTWARE_VERSION,
        },
    }
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/rpc/device_heartbeat",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return 200 <= resp.status < 300
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:200]
        print(f"[Heartbeat] HTTP {e.code}: {detail}")
    except Exception as e:
        print(f"[Heartbeat] Failed: {e}")
    return False


def heartbeat_loop():
    failures = 0
    while not heartbeat_stop.is_set():
        if send_heartbeat():
            if failures:
                print("[Heartbeat] Back online")
            failures = 0
        else:
            failures += 1
        # Sleep until the next beat, or wake early right after a sensor cycle.
        heartbeat_wake.wait(HEARTBEAT_INTERVAL)
        heartbeat_wake.clear()


if SUPABASE_URL and SUPABASE_ANON_KEY:
    threading.Thread(target=heartbeat_loop, name="heartbeat", daemon=True).start()
    print(f"[Heartbeat] Every {HEARTBEAT_INTERVAL}s -> {SUPABASE_URL}")
else:
    print("[Heartbeat] SUPABASE_URL / SUPABASE_ANON_KEY not set -- app will "
          "show status from the last reading only")


# -----------------------------------------------------------------
#  READERS
# -----------------------------------------------------------------
def read_dht22():
    """Returns (temperature, humidity, ok). ok=False means the values
    below are placeholder 0s, not real readings."""
    global sensor, last_good_temp, last_good_humid

    for attempt in range(1, DHT_MAX_RETRY + 1):
        try:

            sensor.trigger()
            time.sleep(0.2)
            temp = sensor.temperature()
            humid = sensor.humidity()

            if (temp is not None and humid is not None
                    and -40 <= temp <= 80
                    and 0 <= humid <= 100):

                last_good_temp = round(temp, 1)
                last_good_humid = round(humid, 1)
                if attempt > 1:
                    print(f"[DHT22] Success on attempt {attempt}")
                return last_good_temp, last_good_humid, True

        except RuntimeError as e:
            if "buffer" in str(e).lower() or "timing" in str(e).lower():
                if attempt < DHT_MAX_RETRY:
                    print(f"[DHT22] Attempt {attempt}/{DHT_MAX_RETRY} "
                          f"failed -- retrying in {DHT_RETRY_DELAY}s")
            else:
                print(f"[DHT22] Unexpected error: {e}")

        time.sleep(DHT_RETRY_DELAY)

    print("[DHT22] All retries failed -- resetting sensor...")
    try:
        # FIX: this library's sensor object has no exit() method --
        # the correct call is cancel().
        sensor.cancel()
    except Exception:
        pass
    time.sleep(2)

    sensor = DHT22.sensor(pi, GPIO_PIN)
    time.sleep(1)

    if last_good_temp is not None:
        print(f"[DHT22] Using last known value: "
              f"{last_good_temp}C {last_good_humid}%")
        return last_good_temp, last_good_humid, True

    print("[DHT22] No reading available -- sending 0/0 as placeholder")
    return 0, 0, False

def read_npk():

    if npk_sensor is None:
        return 0, 0, 0, 0, 0, 0, False
    try:
        r = npk_sensor.read_registers(0, 7, functioncode=3)
        n = r[4]   # Nitrogen
        p = r[5]   # Phosphorus
        k = r[6]   # Potassium
        ph = r[3] / 10.0
        ec = r[2]  # TODO: verify -- shares register with K
        m = r[0] / 10.0  # TODO: verify -- shares register with N
        return n, p, k, ph, ec, m, True
    except Exception as e:
        print(f"[NPK] {e}")
        return 0, 0, 0, 0, 0, 0, False

def read_npk_verified():

    for attempt in range(1, NPK_MAX_RETRY + 1):
        n, p, k, ph, ec, m, ok = read_npk()

        if ok:
            npk_all_zero = (n == 0 and p == 0 and k == 0)
            if not npk_all_zero:
                return n, p, k, ph, ec, m, True
            if ec != 0:
                print("[NPK] NPK is 0 but EC > 0 -- soil has no nutrients, accepting")
                return n, p, k, ph, ec, m, True

        if attempt < NPK_MAX_RETRY:
            print(f"[NPK] Attempt {attempt}/{NPK_MAX_RETRY} gave no valid "
                  f"reading -- retrying in {NPK_RETRY_DELAY}s")
            time.sleep(NPK_RETRY_DELAY)

    print("[NPK] All retries failed -- not sending NPK values this cycle")
    return None, None, None, None, None, None, False


def capture_image():
    """Returns (image_base64, filename, ok). On failure or when skipped
    this cycle, returns (None, None, False) -- there's no meaningful
    numeric "0" for an image, so we keep None here and rely on the ok
    flag / has_image field in the payload instead."""
    if not camera_available:
        return None, None, False
    try:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"harbest_{timestamp}.jpg"

        print("[Camera] Capturing...")
        picam2.capture_file(IMAGE_PATH)

        if not os.path.exists(IMAGE_PATH):
            print("[Camera] Image file not created")
            return None, None, False

        with open(IMAGE_PATH, 'rb') as f:
            image_bytes = f.read()

        image_base64 = base64.b64encode(image_bytes).decode('utf-8')
        size_kb = len(image_bytes) / 1024
        print(f"[Camera] Captured: {filename} ({size_kb:.1f} KB)")

        os.remove(IMAGE_PATH)
        return image_base64, filename, True

    except Exception as e:
        print(f"[Camera] Error: {e}")
        return None, None, False


# -----------------------------------------------------------------
#  EVALUATORS
# -----------------------------------------------------------------
def evaluate_crop_health(temperature, humidity, dht_ok):
    if not dht_ok:
        return "Unknown"
    temp_ok = TEMP_MIN <= temperature <= TEMP_MAX
    hum_ok = HUMID_MIN <= humidity <= HUMID_MAX
    if temp_ok and hum_ok:
        return "Optimal"
    elif not temp_ok and not hum_ok:
        return "Critical"
    elif not temp_ok:
        return "Temperature Warning"
    else:
        return "Humidity Warning"


def evaluate_nutrients(n, p, k, npk_ok):
    if not npk_ok:
        return ["Nutrient data unavailable"]
    recs = []
    if n < N_MIN:
        recs.append(f"Nitrogen low ({n} mg/kg) - apply nitrogen fertilizer")
    if p < P_MIN:
        recs.append(f"Phosphorus low ({p} mg/kg) - apply phosphate fertilizer")
    if k < K_MIN:
        recs.append(f"Potassium low ({k} mg/kg) - apply potassium fertilizer")
    if not recs:
        recs.append("Nutrient levels optimal")
    return recs


def calculate_heat_index(t, h, dht_ok):
    if not dht_ok:
        return 0
    hi = (-8.78469475556 + 1.61139411 * t + 2.33854883889 * h
          - 0.14611605 * t * h - 0.012308094 * t ** 2
          - 0.0164248277778 * h ** 2 + 0.002211732 * t ** 2 * h
          + 0.00072546 * t * h ** 2 - 0.000003582 * t ** 2 * h ** 2)
    return round(hi, 1)


# -----------------------------------------------------------------
#  MAIN LOOP
# -----------------------------------------------------------------
print("\n" + "=" * 50)
print("  HarBest Sensor Node - Running")
print(f"  Broker   : {MQTT_BROKER}:{MQTT_PORT}")
print(f"  Sensor   : every {READ_INTERVAL}s")
print(f"  Camera   : every {CAMERA_INTERVAL}s")
print(f"  Camera   : {'picamera2 (' + str(IMAGE_WIDTH) + 'x' + str(IMAGE_HEIGHT) + ')' if camera_available else 'Not available'}")
print(f"  Status   : {'heartbeat every ' + str(HEARTBEAT_INTERVAL) + 's' if SUPABASE_URL and SUPABASE_ANON_KEY else 'heartbeat off'}")
print("=" * 50 + "\n")

last_camera_time = 0
consecutive_failures = 0

try:
    while True:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        current_time = time.time()

        temperature, humidity, dht_ok = read_dht22()
        nitrogen, phosphorus, potassium, pH, EC, moisture, npk_ok = read_npk_verified()

        # Share this cycle's sensor health with the heartbeat thread and
        # send a beat right away so the app updates without waiting.
        last_dht_ok = dht_ok
        last_npk_ok = npk_ok
        last_read_at = timestamp
        heartbeat_wake.set()

        if not dht_ok:
            consecutive_failures += 1
            print(f"[DHT22] Consecutive failures: {consecutive_failures}")
        else:
            consecutive_failures = 0

        # Default to "no image this cycle" so the payload always has a
        # consistent shape even when the camera interval hasn't elapsed.
        image_base64, image_name, image_ok = None, None, False

        if (camera_available and
                (current_time - last_camera_time) >= CAMERA_INTERVAL):
            image_base64, image_name, image_ok = capture_image()

            if image_ok:
                last_camera_time = current_time

                image_payload = {
                    "device_id": CLIENT_ID,
                    "timestamp": timestamp,
                    "filename": image_name,
                    "image_b64": image_base64,
                    "width": IMAGE_WIDTH,
                    "height": IMAGE_HEIGHT,
                }
                client.publish(
                    MQTT_TOPIC_IMAGE,
                    json.dumps(image_payload),
                    qos=0
                )
                print(f"[Camera] Published to {MQTT_TOPIC_IMAGE}")

        crop_health = evaluate_crop_health(temperature, humidity, dht_ok)
        nutrient_notes = evaluate_nutrients(nitrogen, phosphorus, potassium, npk_ok)
        heat_index = calculate_heat_index(temperature, humidity, dht_ok)

        payload = {
            "device_id": CLIENT_ID,
            "timestamp": timestamp,
            "dht22": {
                "temperature": temperature,
                "humidity": humidity,
                "heat_index": heat_index,
                "ok": dht_ok,
                "unit": {"temperature": "C", "humidity": "%"}
            },
            "npk": {
                "nitrogen": nitrogen,
                "phosphorus": phosphorus,
                "potassium": potassium,
                "unit": "mg/kg",
                "pH": pH,
                "EC": EC,
                "moisture": moisture,
                "ok": npk_ok,
            },
            "analytics": {
                "crop_health": crop_health,
                "nutrient_recommendation": nutrient_notes,
                "sensor_status": {
                    "dht22_ok": dht_ok,
                    "npk_ok": npk_ok,
                    "camera_ok": camera_available
                }
            },
            "has_image": image_ok,
            "image_name": image_name,
        }

        # Always publish -- payload now has a consistent shape regardless
        # of which sensors succeeded this cycle.
        result = client.publish(MQTT_TOPIC_DATA, json.dumps(payload), qos=1)

        print(f"\n[{timestamp}]")
        print(f"  Temp      : {temperature}C  (ok={dht_ok})")
        print(f"  Humidity  : {humidity}%  (ok={dht_ok})")
        print(f"  H.I       : {heat_index}C")
        print(f"   N        : {nitrogen} mg/kg  (ok={npk_ok})")
        print(f"   P        : {phosphorus} mg/kg")
        print(f"   K        : {potassium} mg/kg")
        print(f"   pH       : {pH}")
        print(f"   EC       : {EC}")
        print(f"   moisture : {moisture}")
        print(f"  Health    : {crop_health}")
        print(f"  Nutrients : {' | '.join(nutrient_notes)}")
        print(f"  Image     : {'Captured' if image_ok else 'Skipped'}")
        print(f"  MQTT      : {'Sent' if result.rc == 0 else 'Failed'}")

        time.sleep(READ_INTERVAL)

except KeyboardInterrupt:
    print("\n[HarBest] Shutting down...")
    heartbeat_stop.set()
    heartbeat_wake.set()
    sensor.cancel()  # FIX: was sensor.exit(), which doesn't exist on this library
    if npk_sensor:
        npk_sensor.serial.close()
    if picam2 is not None:
        picam2.stop()
    client.loop_stop()
    client.disconnect()
    pi.stop()
    print("[HarBest] Goodbye")
