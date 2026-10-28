import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
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
      widget.api.product(widget.code!).then((p) => setState(() => _shopProduct = p), onError: (e) => setState(() => _error = '$e'));
    }
  }

  Future<void> _pickLabel(ImageSource source) async {
    final f = await ImagePicker().pickImage(source: source, maxWidth: 2048, imageQuality: 90);
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
      final t = await widget.api.create(product: _product.text, listing: _listing.text, code: widget.code ?? '', label: _label);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TrialScreen(api: widget.api, trialId: t.id, initial: t)));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shop = _shopProduct;
    return Scaffold(
      appBar: AppBar(title: const Text('New trial')),
      body: _busy
          ? const _Thinking('The agent is reading the claims and planning your trial…')
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (shop != null) ...[
                Text(shop['name'], style: text.headlineSmall),
                Text('Trial from ${shop['shop']}', style: text.bodyMedium),
                const SizedBox(height: 16),
              ] else ...[
                TextField(controller: _product, decoration: const InputDecoration(labelText: 'Product name', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                  controller: _listing,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'What does it claim?',
                    hintText: 'Paste the claims from the box or the shop page',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickLabel(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Photo of the label'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: () => _pickLabel(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined)),
                ]),
                if (_label != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_label!, height: 140, fit: BoxFit.cover)),
                  ),
                const SizedBox(height: 16),
              ],
              Text(
                'The agent reads the claims, picks what YouCam Skin AI can measure, and plans how long to test. '
                'It flags ingredients that should not go on a face without a doctor.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: shop != null || widget.code == null ? _submit : null, child: const Text('Plan my trial')),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ]),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ]),
        ),
      );
}
