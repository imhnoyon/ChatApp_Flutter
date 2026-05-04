import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback onLogin;
  const AuthScreen({super.key, required this.onLogin});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _loginUsernameCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  final _regUsernameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regPassword2Ctrl = TextEditingController();
  bool _loading = false;
  bool _loginPassVisible = false;
  bool _regPassVisible = false;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _login() async {
    final u = _loginUsernameCtrl.text.trim();
    final p = _loginPasswordCtrl.text;
    if (u.isEmpty || p.isEmpty) return _showError('Fill in all fields');
    setState(() => _loading = true);
    try {
      await _api.login(u, p);
      if (mounted) widget.onLogin();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final u = _regUsernameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final p = _regPasswordCtrl.text;
    final p2 = _regPassword2Ctrl.text;
    if (u.isEmpty || email.isEmpty || p.isEmpty) {
      return _showError('Fill in all fields');
    }
    if (p != p2) return _showError('Passwords do not match');
    setState(() => _loading = true);
    try {
      await _api.register(u, email, p, p2);
      if (mounted) widget.onLogin();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? kDarkBg : kLightBg;
    final cardColor = isDark ? kDarkCard : kLightCard;
    final textColor = isDark ? kDarkText : kLightText;
    final subColor = isDark ? kDarkSubText : kLightSubText;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  // Logo
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: kBrandGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.chat_bubble_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text('ChatApp',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: textColor)),
                  const SizedBox(height: 4),
                  Text('Secure · Fast · Private',
                      style: TextStyle(color: subColor, fontSize: 13)),
                  const SizedBox(height: 32),

                  // Card
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withAlpha(38), blurRadius: 20)
                      ],
                    ),
                    child: Column(
                      children: [
                        // Tabs
                        Container(
                          decoration: BoxDecoration(
                            color:
                                isDark ? kDarkInput : const Color(0xFFF0F2F5),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16)),
                          ),
                          child: TabBar(
                            controller: _tab,
                            indicator: BoxDecoration(
                              color: kBrandGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicatorPadding: const EdgeInsets.all(6),
                            labelColor: Colors.white,
                            unselectedLabelColor: subColor,
                            dividerColor: Colors.transparent,
                            tabs: const [
                              Tab(text: 'Sign In'),
                              Tab(text: 'Create Account'),
                            ],
                          ),
                        ),

                        // Forms
                        SizedBox(
                          height: 320,
                          child: TabBarView(
                            controller: _tab,
                            children: [
                              _LoginForm(
                                usernameCtrl: _loginUsernameCtrl,
                                passwordCtrl: _loginPasswordCtrl,
                                passVisible: _loginPassVisible,
                                onTogglePass: () => setState(() =>
                                    _loginPassVisible = !_loginPassVisible),
                                onSubmit: _login,
                                loading: _loading,
                                textColor: textColor,
                                subColor: subColor,
                              ),
                              _RegisterForm(
                                usernameCtrl: _regUsernameCtrl,
                                emailCtrl: _regEmailCtrl,
                                passwordCtrl: _regPasswordCtrl,
                                password2Ctrl: _regPassword2Ctrl,
                                passVisible: _regPassVisible,
                                onTogglePass: () => setState(
                                    () => _regPassVisible = !_regPassVisible),
                                onSubmit: _register,
                                loading: _loading,
                                textColor: textColor,
                                subColor: subColor,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 12, color: kBrandGreen),
                      const SizedBox(width: 6),
                      Text('End-to-end encrypted',
                          style: TextStyle(color: subColor, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  final TextEditingController usernameCtrl, passwordCtrl;
  final bool passVisible, loading;
  final VoidCallback onTogglePass, onSubmit;
  final Color textColor, subColor;

  const _LoginForm({
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.passVisible,
    required this.onTogglePass,
    required this.onSubmit,
    required this.loading,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _AuthField(
            ctrl: usernameCtrl,
            hint: 'Username',
            icon: Icons.person_outline,
            textColor: textColor,
          ),
          const SizedBox(height: 12),
          _AuthField(
            ctrl: passwordCtrl,
            hint: 'Password',
            icon: Icons.lock_outline,
            obscure: !passVisible,
            textColor: textColor,
            suffix: IconButton(
              icon: Icon(passVisible ? Icons.visibility_off : Icons.visibility,
                  color: subColor, size: 20),
              onPressed: onTogglePass,
            ),
          ),
          const SizedBox(height: 20),
          _SubmitButton(
            label: 'Sign In',
            icon: Icons.arrow_forward,
            loading: loading,
            onTap: onSubmit,
          ),
        ],
      ),
    );
  }
}

class _RegisterForm extends StatelessWidget {
  final TextEditingController usernameCtrl,
      emailCtrl,
      passwordCtrl,
      password2Ctrl;
  final bool passVisible, loading;
  final VoidCallback onTogglePass, onSubmit;
  final Color textColor, subColor;

  const _RegisterForm({
    required this.usernameCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.password2Ctrl,
    required this.passVisible,
    required this.onTogglePass,
    required this.onSubmit,
    required this.loading,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _AuthField(
              ctrl: usernameCtrl,
              hint: 'Username',
              icon: Icons.person_outline,
              textColor: textColor),
          const SizedBox(height: 10),
          _AuthField(
              ctrl: emailCtrl,
              hint: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textColor: textColor),
          const SizedBox(height: 10),
          _AuthField(
            ctrl: passwordCtrl,
            hint: 'Password',
            icon: Icons.lock_outline,
            obscure: !passVisible,
            textColor: textColor,
            suffix: IconButton(
              icon: Icon(passVisible ? Icons.visibility_off : Icons.visibility,
                  color: subColor, size: 20),
              onPressed: onTogglePass,
            ),
          ),
          const SizedBox(height: 10),
          _AuthField(
              ctrl: password2Ctrl,
              hint: 'Confirm Password',
              icon: Icons.shield_outlined,
              obscure: true,
              textColor: textColor),
          const SizedBox(height: 16),
          _SubmitButton(
              label: 'Create Account',
              icon: Icons.add,
              loading: loading,
              onTap: onSubmit),
        ],
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final Color textColor;

  const _AuthField({
    required this.ctrl,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        suffixIcon: suffix,
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;

  const _SubmitButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onTap,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: kBrandGreen,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
