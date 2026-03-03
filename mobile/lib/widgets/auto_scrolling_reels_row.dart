import 'dart:async';

import 'package:flutter/material.dart';

import 'video_reels.dart';

class AutoScrollingReelsRow extends StatefulWidget {
  final List<String> videoPaths;
  final List<String> logos;
  final List<int>? likesCounts;
  final List<int>? savesCounts;
  final List<bool>? likedStates;
  final List<bool>? savedStates;
  final void Function(int index) onTap;

  final double itemExtent;
  final double step;
  final Duration tick;

  const AutoScrollingReelsRow({
    super.key,
    required this.videoPaths,
    required this.logos,
    this.likesCounts,
    this.savesCounts,
    this.likedStates,
    this.savedStates,
    required this.onTap,
    this.itemExtent = 110,
    this.step = 1.0,
    this.tick = const Duration(milliseconds: 50),
  });

  @override
  State<AutoScrollingReelsRow> createState() => _AutoScrollingReelsRowState();
}

class _AutoScrollingReelsRowState extends State<AutoScrollingReelsRow> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;

  late final int _repeatCount;
  late final int _baseCount;

  @override
  void initState() {
    super.initState();

    _baseCount = widget.videoPaths.length;
    _repeatCount = (_baseCount == 0) ? 1 : 60;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;

      final initialIndex = (_repeatCount * _baseCount) ~/ 2;
      _scrollController.jumpTo(initialIndex * widget.itemExtent);
      _startAutoScroll();
    });
  }

  void _startAutoScroll() {
    _timer?.cancel();
    if (_baseCount <= 1) return;

    _timer = Timer.periodic(widget.tick, (_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;

      final current = _scrollController.offset;
      final next = current + widget.step;

      // حافظ على الإحساس "لا نهائي" بدون رجوع مرئي: نقفز للخلف بمقدار دورة كاملة
      // عند الاقتراب من نهاية القائمة الطويلة.
      final totalItems = _repeatCount * _baseCount;
      final maxSafeOffset = (totalItems - _baseCount) * widget.itemExtent;

      if (next >= maxSafeOffset) {
        _scrollController.jumpTo(next - (_baseCount * widget.itemExtent));
      } else {
        _scrollController.jumpTo(next);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AutoScrollingReelsRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.videoPaths.length != widget.videoPaths.length ||
      oldWidget.logos.length != widget.logos.length ||
      oldWidget.likesCounts?.length != widget.likesCounts?.length ||
      oldWidget.savesCounts?.length != widget.savesCounts?.length ||
      oldWidget.likedStates?.length != widget.likedStates?.length ||
      oldWidget.savedStates?.length != widget.savedStates?.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo((_repeatCount * _baseCount ~/ 2) * widget.itemExtent);
      });

      _startAutoScroll();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videoPaths.isEmpty || widget.logos.isEmpty) {
      return const SizedBox.shrink();
    }

    final itemCount = _repeatCount * widget.videoPaths.length;

    return SizedBox(
      height: 110,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemExtent: widget.itemExtent,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final baseIndex = index % widget.videoPaths.length;
          final logo = widget.logos[index % widget.logos.length];
            final likes = (widget.likesCounts != null && baseIndex < widget.likesCounts!.length)
              ? widget.likesCounts![baseIndex]
              : 0;
            final saves = (widget.savesCounts != null && baseIndex < widget.savesCounts!.length)
              ? widget.savesCounts![baseIndex]
              : 0;
            final isLiked = (widget.likedStates != null && baseIndex < widget.likedStates!.length)
              ? widget.likedStates![baseIndex]
              : false;
            final isSaved = (widget.savedStates != null && baseIndex < widget.savedStates!.length)
              ? widget.savedStates![baseIndex]
              : false;
          return Center(
            child: VideoThumbnailWidget(
              path: widget.videoPaths[baseIndex],
              logo: logo,
              likesCount: likes,
              savesCount: saves,
              isLiked: isLiked,
              isSaved: isSaved,
              margin: EdgeInsets.zero,
              onTap: () => widget.onTap(baseIndex),
            ),
          );
        },
      ),
    );
  }
}
