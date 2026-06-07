import 'package:flutter/services.dart';

const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

String googleSignInErrorMessage(Object error) {
  if (error is PlatformException && error.code == 'sign_in_failed') {
    final details = error.details?.toString() ?? '';
    if (details.contains('10:')) {
      return 'Configuratia Google Sign-In nu se potriveste cu aplicatia Android. '
          'Verifica OAuth client-ul Android pentru package com.laurentiu.chat_social '
          'si SHA-1 98:A3:7D:88:66:4E:33:1B:96:21:29:57:B9:0B:E5:F9:EF:A0:18:C8, '
          'apoi ruleaza din nou aplicatia cu GOOGLE_WEB_CLIENT_ID setat la Web client ID.';
    }
  }

  return 'Eroare Google Sign-In: $error';
}
