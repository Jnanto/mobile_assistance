import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/services/profile_services.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    runApp(FirebaseSetupErrorApp(error: error));
    return;
  }

  await FirebaseAuth.instance.setLanguageCode('es');
  final prefs = await SharedPreferencesStore.load();
  runApp(SelvaCheckApp(prefs: prefs));
}
