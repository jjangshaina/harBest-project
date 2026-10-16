import 'package:flutter/material.dart';
import '../theme/app_style.dart';

/// The standard text field for the sign-in / sign-up screens: grey rounded
/// box that turns white with a green outline while typing, and gets a red
/// outline plus a message under it when [showError] is true.
class AppTextField extends StatefulWidget {
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final bool autocorrect;
  final Widget? suffix;
  final bool showError;
  final String errorText;

  const AppTextField({
    super.key,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.onChanged,
    this.obscureText = false,
    this.autocorrect = true,
    this.suffix,
    this.showError = false,
    this.errorText = 'This field is required',
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.field);
    const red = BorderSide(color: AppColors.onDarkError, width: 2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            autocorrect: widget.autocorrect,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              hintText: widget.hint,
              filled: true,
              fillColor: _focus.hasFocus ? Colors.white : AppColors.authField,
              suffixIcon: widget.suffix,
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: widget.showError ? red : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: widget.showError
                    ? red
                    : const BorderSide(color: AppColors.authAccent, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
          ),
          if (widget.showError)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Text(
                widget.errorText,
                style: const TextStyle(
                  color: AppColors.onDarkError,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// [AppTextField] with the show / hide eye button.
class AppPasswordField extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final bool isVisible;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;
  final bool showError;
  final String errorText;

  const AppPasswordField({
    super.key,
    required this.hint,
    required this.controller,
    required this.isVisible,
    required this.onToggle,
    this.onChanged,
    this.showError = false,
    this.errorText = 'This field is required',
  });

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      hint: hint,
      controller: controller,
      obscureText: !isVisible,
      onChanged: onChanged,
      showError: showError,
      errorText: errorText,
      suffix: IconButton(
        icon: Icon(
          isVisible ? AppIcons.visible : AppIcons.hidden,
          color: AppColors.textSecondary,
        ),
        onPressed: onToggle,
      ),
    );
  }
}

/// Text field for normal (light) pages, with a floating label and optional
/// validator for use inside a [Form]. Pass [onToggleObscure] to get the
/// show / hide eye button (password fields).
class AppFormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final String? Function(String?)? validator;

  const AppFormField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.onToggleObscure,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.field);
    final noLine = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    );
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: AppText.body,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.label.copyWith(fontSize: 15),
        filled: true,
        fillColor: AppColors.fieldLight,
        border: noLine,
        enabledBorder: noLine,
        focusedBorder: noLine,
        errorBorder: noLine,
        focusedErrorBorder: noLine,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                icon: Icon(
                  obscure ? AppIcons.hidden : AppIcons.visible,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
                onPressed: onToggleObscure,
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// AUTH PAGES: labeled fields for the white card
// ─────────────────────────────────────────────────────────────────────────

/// Labeled text field with a leading icon, for the white auth card.
class AuthField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final bool autocorrect;
  final bool showError;
  final String errorText;
  final String? helperText;
  final Widget? suffix;

  const AuthField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.onChanged,
    this.obscureText = false,
    this.autocorrect = true,
    this.showError = false,
    this.errorText = 'This field is required',
    this.helperText,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.field);
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c, width: w),
        );
    final idle = showError ? AppColors.critical : AppColors.darkGreen;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            autocorrect: autocorrect,
            onChanged: onChanged,
            style: AppText.body,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
              filled: true,
              fillColor: Colors.white,
              prefixIcon: Icon(icon, size: 20, color: AppColors.darkGreen),
              suffixIcon: suffix,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              border: border(idle, 1.2),
              enabledBorder: border(idle, 1.2),
              focusedBorder:
                  border(showError ? AppColors.critical : AppColors.green, 2),
            ),
          ),
          if (showError)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                errorText,
                style: const TextStyle(
                  color: AppColors.critical,
                  fontSize: 12,
                ),
              ),
            )
          else if (helperText != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(helperText!, style: AppText.caption),
            ),
        ],
      ),
    );
  }
}

/// [AuthField] with the show / hide eye button.
class AuthPasswordField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool isVisible;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;
  final bool showError;
  final String errorText;
  final String? helperText;

  const AuthPasswordField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.isVisible,
    required this.onToggle,
    this.onChanged,
    this.showError = false,
    this.errorText = 'This field is required',
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return AuthField(
      label: label,
      hint: hint,
      icon: AppIcons.lock,
      controller: controller,
      obscureText: !isVisible,
      onChanged: onChanged,
      showError: showError,
      errorText: errorText,
      helperText: helperText,
      suffix: IconButton(
        icon: Icon(
          isVisible ? AppIcons.visible : AppIcons.hidden,
          color: AppColors.textPrimary,
          size: 22,
        ),
        onPressed: onToggle,
      ),
    );
  }
}