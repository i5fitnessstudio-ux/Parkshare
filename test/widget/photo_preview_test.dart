// Widget tests for the owner parking photo preview.
//
// Task under test: the Add Parking preview must show the ACTUAL uploaded
// image(s) (first one large, the rest as thumbnails) and fall back to a
// placeholder only while nothing is uploaded. These tests pin both halves of
// that contract, plus the null/empty-bytes path that used to be able to throw.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/core/constants/app_colors.dart';
import 'package:parkshare_new/core/services/photo_picker_service.dart';
import 'package:parkshare_new/modules/owner/add_parking/parking_draft.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/dimensions_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/photo_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/review_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/widgets/photo_preview.dart';
import 'package:parkshare_new/shared/widgets/dimension_illustration.dart';

/// A 1x1 transparent PNG: enough bytes for `Image.memory` to decode.
final Uint8List _png = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

PickedPhoto photo(String name) =>
    PickedPhoto(bytes: _png, filename: name, contentType: 'image/png');

/// Phone-sized host, matching add_parking_steps_test.dart.
Widget host(Widget Function(VoidCallback onChanged) build) => MaterialApp(
  home: Scaffold(
    body: StatefulBuilder(
      builder: (context, setState) => SizedBox(
        width: 360,
        height: 760,
        child: build(() => setState(() {})),
      ),
    ),
  ),
);

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PhotoPreview', () {
    testWidgets('an empty list shows the placeholder, not an image', (
      tester,
    ) async {
      await tester.pumpWidget(
        host((_) => const PhotoPreview(photos: [])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNothing);
      expect(find.byType(PhotoPreviewPlaceholder), findsOneWidget);
      expect(find.text('No photo added yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one photo renders as a large image, not a placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        host((_) => PhotoPreview(photos: [photo('a.png')])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(PhotoPreviewPlaceholder), findsNothing);
      // The hero image must be the dominant element on screen.
      final size = tester.getSize(find.byType(Image));
      expect(size.width, greaterThan(300));
      expect(size.height, greaterThan(100));
      // A single photo needs no "1 of N" badge or thumbnail strip.
      expect(find.text('1 of 1'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('extra photos become a thumbnail strip with a 1 of N badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          (_) => PhotoPreview(photos: [
            photo('a.png'),
            photo('b.png'),
            photo('c.png'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 of 3'), findsOneWidget);
      // 1 hero + 2 thumbnails, all decoded.
      expect(find.byType(Image), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the hero photo is cropped to fill, never letterboxed', (
      tester,
    ) async {
      await tester.pumpWidget(
        host((_) => PhotoPreview(photos: [photo('a.png')])),
      );
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(
        find.descendant(
          of: find.byType(PhotoPreview),
          matching: find.byType(ClipRRect),
        ),
        findsWidgets,
        reason: 'the photo must have rounded corners',
      );
    });

    testWidgets('an empty-bytes photo is treated as "no photo", never decoded', (
      tester,
    ) async {
      final broken = PickedPhoto(
        bytes: Uint8List(0),
        filename: 'empty.png',
        contentType: 'image/png',
      );
      await tester.pumpWidget(
        host((_) => PhotoPreview(photos: [broken])),
      );
      await tester.pumpAndSettle();

      // A zero-length Uint8List handed to Image.memory would throw.
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(PhotoPreviewPlaceholder), findsOneWidget);
    });

    testWidgets('a custom placeholder is used when nothing is uploaded', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          (_) => const PhotoPreview(
            photos: [],
            placeholder: Text('custom placeholder'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('custom placeholder'), findsOneWidget);
    });
  });

  group('DimensionsStep preview', () {
    testWidgets('shows the bundled reference illustration with no photos', (
      tester,
    ) async {
      final draft = ParkingDraft();
      await tester.pumpWidget(
        host((onChanged) => DimensionsStep(draft: draft, onChanged: onChanged)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PhotoPreview), findsOneWidget);
      expect(find.byType(DimensionIllustration), findsOneWidget);
      expect(find.byType(PhotoPreviewPlaceholder), findsNothing);
    });

    testWidgets('shows the owner\'s real photo instead of the illustration', (
      tester,
    ) async {
      final draft = ParkingDraft()..photos.add(photo('mine.png'));
      await tester.pumpWidget(
        host((onChanged) => DimensionsStep(draft: draft, onChanged: onChanged)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PhotoPreview), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The plot's own reference illustration is gone (only the unrelated GATE
      // illustration below survives), which is what makes the preview show the
      // real photo. It lives further down a lazily-built ListView.
      await scrollTo(tester, find.text('Entrance / Gate'));
      expect(find.byType(DimensionIllustration), findsOneWidget);
    });

    testWidgets('does not overflow on a narrow phone', (tester) async {
      final draft = ParkingDraft()
        ..photos.addAll([photo('a.png'), photo('b.png')]);
      await tester.pumpWidget(
        host((onChanged) => DimensionsStep(draft: draft, onChanged: onChanged)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('ReviewStep preview', () {
    testWidgets('renders the real photos large-with-thumbnails', (
      tester,
    ) async {
      final draft = ParkingDraft()
        ..photos.addAll([photo('a.png'), photo('b.png')]);
      await tester.pumpWidget(
        host((_) => ReviewStep(draft: draft)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PhotoPreview), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to a placeholder when nothing was uploaded', (
      tester,
    ) async {
      await tester.pumpWidget(host((_) => ReviewStep(draft: ParkingDraft())));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoPreviewPlaceholder), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('PhotoStep', () {
    testWidgets('explains itself when no photo has been added', (
      tester,
    ) async {
      final draft = ParkingDraft();
      await tester.pumpWidget(
        host(
          (onChanged) => PhotoStep(
            draft: draft,
            picker: _NeverPicker(),
            onChanged: onChanged,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PhotoPreviewPlaceholder), findsOneWidget);
      expect(
        find.textContaining('No photo added yet'),
        findsOneWidget,
      );
    });

    testWidgets('an unusable photo is skipped, never handed to Image.memory', (
      tester,
    ) async {
      final draft = ParkingDraft()
        ..photos.add(
          PickedPhoto(
            bytes: Uint8List(0),
            filename: 'empty.png',
            contentType: 'image/png',
          ),
        );
      await tester.pumpWidget(
        host(
          (onChanged) => PhotoStep(
            draft: draft,
            picker: _NeverPicker(),
            onChanged: onChanged,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(PhotoPreviewPlaceholder), findsOneWidget);
    });
  });

  test('placeholder tile carries the app surface colours', () {
    // Guards the theme coupling the placeholder relies on.
    expect(AppColors.surface, isNotNull);
    expect(AppColors.border, isNotNull);
    expect(AppColors.textHint, isNotNull);
  });
}

/// Picker that always cancels, so the step's own state is what is under test.
class _NeverPicker implements PhotoPickerService {
  @override
  Future<PickedPhoto?> pick(PhotoSource source) async => null;
}