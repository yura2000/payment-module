/// The identity of a Brand, matched 1:1 with an Android product flavor of the same name.
/// An open string type — never a closed enum — so nothing in the codebase can `switch`
/// exhaustively over the set of Brands. See docs/adr/0002-brand-selection-by-dart-define-and-registry.md
/// and CONTEXT.md → Brand, Flavor.
extension type const BrandId(String value) {}
