class Binding {
  String event;
  BindingCallback callback;
  String? type;

  Binding(
    this.event,
    this.callback, [
    this.type,
  ]);
}

typedef BindingCallback = void Function(dynamic payload, {String? ref});
