import 'package:flutter/cupertino.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import 'home_screen.dart';

/// Shows sign-in or the person's classrooms, following the account as it changes.
class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.backend,
    required this.onBrightnessChanged,
  });

  final Backend backend;
  final ValueChanged<Brightness> onBrightnessChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: backend.user,
      builder: (context, snapshot) {
        final Widget page;
        if (snapshot.connectionState == ConnectionState.waiting) {
          page = const _Loading();
        } else if (snapshot.data == null) {
          page = SignInScreen(backend: backend);
        } else {
          page = HomeScreen(
            key: ValueKey(snapshot.data!.uid),
            backend: backend,
            onBrightnessChanged: onBrightnessChanged,
          );
        }
        return page;
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Stack(
    fit: StackFit.expand,
    children: [
      AmbientBackdrop(),
      Center(child: CupertinoActivityIndicator()),
    ],
  );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.backend});

  final Backend backend;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _registering = false;
  var _busy = false;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on BackendFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _message = 'Enter your email and password.');
      return;
    }
    if (_registering && _name.text.trim().isEmpty) {
      setState(
        () => _message = 'Enter your name, so your team knows it’s you.',
      );
      return;
    }
    _run(
      () => _registering
          ? widget.backend.registerWithEmail(_name.text, email, _password.text)
          : widget.backend.signInWithEmail(email, _password.text),
    );
  }

  void _reset() {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _message = 'Enter your email first, then tap this again.');
      return;
    }
    _run(() async {
      await widget.backend.sendPasswordReset(email);
      if (mounted) {
        setState(() => _message = 'A reset link is on its way to $email.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const AmbientBackdrop(),
        BackdropGroup(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: GlassPanel(
                    radius: 28,
                    weight: GlassWeight.thick,
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Octria',
                          style: TypeRamp.title(p.ink)
                              .copyWith(fontSize: 28, letterSpacing: -0.7),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Turn any task into a classroom with a plan.',
                          style: TypeRamp.body(p.inkSoft),
                        ),
                        const SizedBox(height: 22),
                        PressButton(
                          label: 'Continue with Google',
                          height: 44,
                          expand: true,
                          onTap: _busy
                              ? null
                              : () => _run(widget.backend.signInWithGoogle),
                        ),
                        const SizedBox(height: 8),
                        PressButton(
                          label: 'Continue with GitHub',
                          height: 44,
                          expand: true,
                          onTap: _busy
                              ? null
                              : () => _run(widget.backend.signInWithGitHub),
                        ),
                        const SizedBox(height: 20),
                        if (_registering) ...[
                          GlassField(
                            label: 'Your name',
                            controller: _name,
                            autofillHints: const [AutofillHints.name],
                          ),
                          const SizedBox(height: 10),
                        ],
                        GlassField(
                          label: 'Email',
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                        ),
                        const SizedBox(height: 10),
                        GlassField(
                          label: 'Password',
                          controller: _password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _message!,
                              style: TypeRamp.label(p.inkSoft),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        PressButton(
                          label: _registering ? 'Create account' : 'Sign in',
                          prominent: true,
                          height: 44,
                          expand: true,
                          onTap: _busy ? null : _submit,
                        ),
                        const SizedBox(height: 4),
                        PressButton(
                          label: _registering
                              ? 'I already have an account'
                              : 'Create an account',
                          quiet: true,
                          height: 44,
                          expand: true,
                          onTap: () => setState(() {
                            _registering = !_registering;
                            _message = null;
                          }),
                        ),
                        if (!_registering)
                          PressButton(
                            label: 'Forgot password',
                            quiet: true,
                            height: 44,
                            expand: true,
                            onTap: _busy ? null : _reset,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
