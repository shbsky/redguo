import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SearchInput extends StatefulWidget {
  const SearchInput({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSearch,
    this.onChanged,
    this.suggestions,
    this.onCancel,
    this.focusNode,
    this.autofocus = false,
    this.onNavigateUp,
    this.onNavigateDown,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSearch;
  final ValueChanged<String>? onChanged;
  final Future<List<String>> Function(String)? suggestions;
  final VoidCallback? onCancel;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  @override
  State<SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<SearchInput> {
  FocusNode? _owned;
  FocusNode get _focus {
    final node = widget.focusNode;
    return node ?? (_owned ??= FocusNode());
  }
  Timer? _timer;
  Completer<Iterable<String>>? _pending;
  int _generation = 0;
  bool _selected = false;
  bool _suggesting = false;
  final _cache = <String, List<String>>{};

  KeyEventResult _verticalKey(FocusNode node, KeyEvent event) {
    if (_suggesting || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown && widget.onNavigateDown != null) {
      widget.onNavigateDown!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && widget.onNavigateUp != null) {
      widget.onNavigateUp!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _cancel() {
    _timer?.cancel();
    widget.onCancel?.call();
    _generation++;
    _suggesting = false;
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.complete(const []);
    }
  }

  @override
  void didUpdateWidget(SearchInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suggestions == null) _cancel();
  }

  @override
  void dispose() {
    _cancel();
    _owned?.dispose();
    super.dispose();
  }

  Future<Iterable<String>> _options(TextEditingValue value) async {
    _cancel();
    final query = value.text.trim();
    if (query.isEmpty ||
        query.length > 100 ||
        widget.suggestions == null ||
        !value.composing.isCollapsed) {
      return const [];
    }
    if (_cache.containsKey(query)) {
      _suggesting = _cache[query]!.isNotEmpty;
      return _cache[query]!;
    }
    final generation = _generation;
    final pending = Completer<Iterable<String>>();
    _pending = pending;
    _timer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = (await widget.suggestions!(
          query,
        )).where((s) => s.trim().isNotEmpty).toSet().take(10).toList();
        if (generation == _generation && mounted) {
          if (_cache.length >= 32) _cache.remove(_cache.keys.first);
          _cache[query] = result;
          _suggesting = result.isNotEmpty;
          if (!pending.isCompleted) pending.complete(result);
        }
      } catch (_) {}
      if (!pending.isCompleted) pending.complete(const []);
    });
    return pending.future;
  }

  void _submit(String value) {
    _cancel();
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _focus.unfocus();
    widget.onSearch(value.trim());
  }

  Widget _highlight(String value) {
    final query = widget.controller.text.trim().toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (query.isNotEmpty) {
      final match = value.toLowerCase().indexOf(query, start);
      if (match < 0) break;
      if (match > start) {
        spans.add(TextSpan(text: value.substring(start, match)));
      }
      spans.add(
        TextSpan(
          text: value.substring(match, match + query.length),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = match + query.length;
    }
    if (start < value.length) spans.add(TextSpan(text: value.substring(start)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: _options,
      onSelected: (value) {
        _selected = true;
        _submit(value);
      },
      fieldViewBuilder: (context, controller, focus, submitted) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _verticalKey,
        child: TextField(
          controller: controller,
          focusNode: focus,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            widget.onChanged?.call(value);
            setState(() {});
          },
          onSubmitted: (value) {
            _selected = false;
            submitted();
            if (!_selected) _submit(value);
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.text.isNotEmpty)
                  IconButton(
                    tooltip: '清空搜索',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _cancel();
                      controller.clear();
                      widget.onChanged?.call('');
                      setState(() {});
                    },
                  ),
                IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => _submit(controller.text),
                ),
              ],
            ),
          ),
        ),
      ),
      optionsViewBuilder: (context, selected, options) {
        final values = options.toList();
        final available =
            MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: constraints.maxWidth,
              height: min(
                min(300.0, max(96.0, available * .45)),
                values.length * 48.0,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemExtent: 48,
                itemCount: values.length,
                itemBuilder: (context, index) => ListTile(
                  key: ValueKey('search-suggestion-$index'),
                  selected: AutocompleteHighlightedOption.of(context) == index,
                  leading: const Icon(Icons.search, size: 18),
                  title: _highlight(values[index]),
                  onTap: () => selected(values[index]),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
