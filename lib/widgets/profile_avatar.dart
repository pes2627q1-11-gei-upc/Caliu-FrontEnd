import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/avatar_api.dart';
import '../data/avatar_controller.dart';
import '../square_crop_screen.dart';
import '../theme/caliu_colors.dart';

/// Tria una imatge de la càmera o de la galeria. Els tests en posen un de fals.
typedef AvatarPicker = Future<XFile?> Function(ImageSource source);

Future<XFile?> _defaultPicker(ImageSource source) =>
    ImagePicker().pickImage(source: source);

/// Avatar del propi perfil amb opció de canviar la foto (tasca #150,
/// H.U #35): càmera o galeria, validació de tipus i mida, retall en quadrat
/// i pujada.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.username,
    this.controller,
    this.picker,
    this.radius = 20,
  });

  final String? username;

  /// Per defecte, [AvatarController.shared].
  final AvatarController? controller;

  /// Per defecte, `image_picker`.
  final AvatarPicker? picker;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatar = controller ?? AvatarController.shared;
    return ListenableBuilder(
      listenable: avatar,
      builder: (context, _) {
        final bytes = avatar.bytes;
        final name = username?.trim() ?? '';
        return Semantics(
          button: true,
          label: 'Canvia la foto de perfil',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: avatar.isUploading
                ? null
                : () => _changePhoto(context, avatar),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  key: const Key('profile-avatar'),
                  radius: radius,
                  backgroundColor: CaliuColors.maroon,
                  foregroundColor: Colors.white,
                  foregroundImage: bytes != null ? MemoryImage(bytes) : null,
                  child: Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: radius * 0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (avatar.isUploading)
                  Positioned.fill(
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: SizedBox.square(
                        dimension: radius,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: CircleAvatar(
                    radius: radius * 0.45,
                    backgroundColor: CaliuColors.red,
                    foregroundColor: Colors.white,
                    child: Icon(Icons.photo_camera, size: radius * 0.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _changePhoto(
    BuildContext context,
    AvatarController avatar,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Fes una foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Tria de la galeria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final XFile? file;
    try {
      file = await (picker ?? _defaultPicker)(source);
    } catch (_) {
      _show(messenger, 'No s\'ha pogut obrir la càmera o la galeria');
      return;
    }
    if (file == null) return;

    final size = await file.length();
    final invalid = AvatarRules.validate(fileName: file.name, sizeBytes: size);
    if (invalid != null) {
      _show(messenger, invalid);
      return;
    }

    final original = await file.readAsBytes();
    final cropped = await navigator.push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (_) => SquareCropScreen(imageBytes: original),
      ),
    );
    if (cropped == null) return;

    try {
      // El retall es desa en PNG.
      await avatar.upload(cropped, contentType: 'image/png');
      _show(messenger, 'Foto de perfil actualitzada');
    } on AvatarApiException catch (e) {
      _show(messenger, e.message);
    } catch (_) {
      _show(messenger, 'No s\'ha pogut pujar la foto');
    }
  }

  void _show(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
