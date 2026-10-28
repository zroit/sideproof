import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'brand.dart';
import 'theme.dart';
import 'trial_screen.dart';

/// Name the product and show its claims; the agent turns them into a trial plan.
class NewTrialScreen extends StatefulWidget {
  const NewTrialScreen({super.key, required this.api, this.code});
  final Api api;
  final String? code;

  @override
  State<NewTrialScreen> createState() => _NewTrialScreenState();
}

class _NewTrialScreenState extends State<NewTrialScreen> {
  final _product = TextEditingController();
  final _listing = TextEditingController();
  Uint8List? _label;
  Map<String, dynamic>? _shopProduct;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.code != null) {
      widget.api
          .product(widget.code!)
          .then(
            (p) => setState(() => _shopProduct = p),
            onError: (e) => setState(() => _error = '$e'),
          );
    }
  }

  Future<void> _pickLabel(ImageSource source) async {
    final f = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      imageQuality: 90,
    );
    if (f != null) {
      final bytes = await f.readAsBytes();
      setState(() => _label = bytes);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await widget.api.create(
        product: _product.text,
        listing: _listing.text,
        code: widget.code ?? '',
        label: _label,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TrialScreen(api: widget.api, trialId: t.id, initial: t),
        ),
      );
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final shop = _shopProduct;
    return Scaffold(
      appBar: AppBar(title: const Text('New trial')),
      body: _busy
          ? const _Thinking(
              'The agent is reading the claims and planning your trial',
            )
          : SafeArea(
              top: false,
              child: Column560(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    if (shop != null) ...[
                      Text(shop['name'], style: text.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        'A trial from ${shop['shop']}',
                        style: text.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ] else ...[
                      Text('What are you testing?', style: text.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        'Give the agent the claims, typed or as a photo of the label.',
                        style: text.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _product,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Product name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _listing,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'What does it claim?',
                          hintText:
                              'Paste the claims from the box or the shop page',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickLabel(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Photo of the label'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            onPressed: () => _pickLabel(ImageSource.gallery),
                            tooltip: 'Choose a photo',
                            style: IconButton.styleFrom(
                              minimumSize: const Size(50, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.photo_library_outlined),
                          ),
                        ],
                      ),
                      if (_label != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.memory(
                              _label!,
                              height: 150,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 20,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'The agent picks what YouCam Skin AI can measure, plans how long to test, and flags ingredients that should not go on a face without a doctor.',
                              style: text.bodyMedium?.copyWith(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: shop != null || widget.code == null
                          ? _submit
                          : null,
                      child: const Text('Plan my trial'),
                    ),
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// While the agent plans: the face with a scan line passing over it.
class _Thinking extends StatefulWidget {
  const _Thinking(this.message);
  final String message;

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.of(context).disableAnimations && !_c.isAnimating)
      _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: FaceScene(
                    line: scheme.onSurface.withValues(alpha: 0.75),
                    treated: Sp.treated(context),
                    control: Sp.control(context),
                    tint: 1,
                    scan: _c.value,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'This takes up to a minute.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
