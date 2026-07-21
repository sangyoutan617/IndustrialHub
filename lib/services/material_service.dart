import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/raw_material.dart';

class MaterialService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<RawMaterial>> getMaterials(int factoryId) async {
    final rows = await _client
        .from('raw_materials')
        .select()
        .eq('factory_id', factoryId)
        .order('material_name', ascending: true);
    return (rows as List)
        .map((row) => RawMaterial.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<RawMaterial> createMaterial(RawMaterial material) async {
    final row = await _client
        .from('raw_materials')
        .insert(material.toInsertJson(material.factoryId))
        .select()
        .single();
    return RawMaterial.fromJson(row);
  }

  Future<RawMaterial> updateMaterial(
    int materialId,
    RawMaterial material,
  ) async {
    final row = await _client
        .from('raw_materials')
        .update({
          ...material.toInsertJson(material.factoryId),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('material_id', materialId)
        .select()
        .single();
    return RawMaterial.fromJson(row);
  }

  Future<void> deleteMaterial(int materialId) async {
    await _client.from('raw_materials').delete().eq('material_id', materialId);
  }
}
