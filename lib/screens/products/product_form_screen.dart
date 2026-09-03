import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/stock_service.dart';
import '../../widgets/responsive_form_fields.dart';

const _maxUnitLength = 20;

class ProductFormScreen extends StatefulWidget {
  final int factoryId;
  final Product? product;

  const ProductFormScreen({super.key, required this.factoryId, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProductService();
  final _stockService = StockService();

  late final _nameController = TextEditingController(
    text: widget.product?.productName,
  );
  late final _unitController = TextEditingController(
    text: widget.product?.unit ?? 'units',
  );
  bool _isSaving = false;

  bool get _isEditing => widget.product != null;

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final product = Product(
        productId: widget.product?.productId ?? 0,
        factoryId: widget.factoryId,
        productName: _nameController.text.trim(),
        unit: _unitController.text.trim().isEmpty
            ? 'units'
            : _unitController.text.trim(),
      );
      if (_isEditing) {
        await _service.updateProduct(widget.product!.productId, product);
      } else {
        final created = await _service.createProduct(product);
        try {
          await _stockService.createStock(widget.factoryId, created, 0);
        } catch (e) {
          debugPrint('products: failed to create initial stock row: $e');
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save product. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit product' : 'Add product')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ResponsiveFormFields(
                children: [
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Product name'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.l),
                  TextFormField(
                    controller: _unitController,
                    maxLength: _maxUnitLength,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      helperText: 'e.g. units, bottles, boxes, litres',
                      helperMaxLines: 2,
                    ),
                    validator: (v) {
                      if (v != null && RegExp(r'[0-9]').hasMatch(v)) {
                        return 'Unit must contain letters only';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FormBreak(
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
