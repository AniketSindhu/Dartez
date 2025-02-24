import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:dartez/chain/tezos/tezos_message_utils.dart';
import 'package:dartez/helper/password_generater.dart';
import 'package:dartez/utils/crypto_utils.dart';
import 'package:secp256k1/secp256k1.dart' as secp256k1;

enum SignerCurve {
  ED25519,
  SECP256K1,

  /// secp256k1 curve is only supported for reading the key not for signing an operation
  SECP256R1,
}

class SoftSigner {
  var _secretKey;
  var _lockTimout;
  late var _passphrase;
  late var _salt;
  late var _unlocked;
  var _key;
  SignerCurve signerCurve = SignerCurve.ED25519;

  SoftSigner(
      {Uint8List? secretKey,
      int validity = -1,
      String passphrase = '',
      Uint8List? salt,
      SignerCurve signerCurve = SignerCurve.ED25519}) {
    this._secretKey = secretKey;
    this._lockTimout = validity;
    this._passphrase = passphrase;
    this._salt = salt != null ? salt : Uint8List(0);
    this._unlocked = validity < 0;
    this._key = Uint8List(0);
    this.signerCurve = signerCurve;
    if (validity < 0) {
      this._key = secretKey;
    }
  }

  static SoftSigner createSigner(Uint8List secretKey, int validity,
      {signerCurve = SignerCurve.ED25519}) {
    if (validity >= 0) {
      var passphrase = PasswordGenerator.generatePassword(
        length: 32,
      );
      var salt = CryptoUtils.generateSaltForPwHash();
      secretKey = CryptoUtils.encryptMessage(secretKey, passphrase, salt);
      return SoftSigner(
          secretKey: secretKey,
          validity: validity,
          passphrase: passphrase,
          salt: salt,
          signerCurve: signerCurve);
    } else
      return new SoftSigner(secretKey: secretKey, signerCurve: signerCurve);
  }

  Uint8List? getKey() {
    if (!_unlocked) {
      var k = CryptoUtils.decryptMessage(_secretKey, _passphrase, _salt);
      if (_lockTimout == 0) {
        return k;
      }
      _key = k;
      _unlocked = true;
      if (_lockTimout > 0) {
        Future.delayed(Duration(milliseconds: _lockTimout * 1000), () {
          _key = Uint8List(0);
          _unlocked = false;
        });
      }
      return _key;
    }
    return _key;
  }

  Uint8List signOperation(Uint8List uint8list) {
    if (signerCurve == SignerCurve.SECP256K1) {
      var key = secp256k1.PrivateKey.fromHex(hex.encode(getKey()!));
      var sig = key
          .signature(hex.encode(TezosMessageUtils.simpleHash(uint8list, 256)));
      return Uint8List.fromList(hex.decode(sig.toRawHex()));
    }

    return CryptoUtils.signDetached(
        TezosMessageUtils.simpleHash(uint8list, 256),
        Uint8List.fromList(getKey()!));
  }

  SignerCurve getSignerCurve() {
    return signerCurve;
  }
}
