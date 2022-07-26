class Binding {
  String? event;
  BindingCallback callback;
  String? type;
  Map<String, String>? filter;

  Binding({
    this.event,
    required this.callback,
    this.type,
    this.filter,
  });
}

typedef BindingCallback = void Function(dynamic payload, {String? ref});
