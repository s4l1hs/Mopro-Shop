import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// One node in the derived category tree.
///
/// The `categoriesProvider` returns a FLAT `List<Category>`; this tree shape
/// is what the mega menu (and any future tree-shaped UI) actually needs. Kept
/// as a derived provider so the source-of-truth fetch stays in one place.
class CategoryNode {
  CategoryNode({required this.category, List<CategoryNode>? children})
      : children = children ?? <CategoryNode>[];

  final Category category;
  final List<CategoryNode> children;

  int get id => category.id;
  String get name => category.name;

  /// Top-level-only promo card payload for the desktop mega menu's 3+1
  /// layout (Session 4d §3). Always null on subcategories and leaves; the
  /// backend enforces this contract at `internal/catalog/repository.go`.
  CategoryPromoSlot? get promoSlot => category.promoSlot;
}

/// Derived: builds a tree from the flat categoriesProvider output. Roots are
/// nodes whose `parent_id` is null. Returns `AsyncData([])` while parents are
/// still loading; preserves loading/error states from upstream.
final categoryTreeProvider = Provider<AsyncValue<List<CategoryNode>>>((ref) {
  final asyncCats = ref.watch(categoriesProvider).categories;
  return asyncCats.whenData(_buildTree);
});

/// O(n) tree build via two passes: first index by id, then attach children
/// based on parent_id. Cycles or dangling parent_ids are silently ignored
/// (the orphan becomes its own root).
List<CategoryNode> _buildTree(List<Category> flat) {
  final byId = <int, CategoryNode>{};
  for (final c in flat) {
    byId[c.id] = CategoryNode(category: c);
  }
  final roots = <CategoryNode>[];
  for (final c in flat) {
    final node = byId[c.id]!;
    final pid = c.parentId;
    if (pid == null) {
      roots.add(node);
    } else {
      final parent = byId[pid];
      if (parent != null) {
        parent.children.add(node);
      } else {
        // Dangling parent_id — treat as root rather than dropping it.
        roots.add(node);
      }
    }
  }
  return roots;
}
