import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' as Foundation;
import 'package:flutter/services.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:intl/intl_standalone.dart';
import 'package:yaml/yaml.dart';
import 'package:devicelocale/devicelocale.dart';

class FlutterI18n {
  static RegExp _parameterRegexp = new RegExp("{(.+)}");
  final bool _useCountryCode;
  final String _fallbackFile;
  final String _basePath;
  Locale forcedLocale;

  Locale locale;

  Map<dynamic, dynamic> decodedMap;

  FlutterI18n(this._useCountryCode,
      [this._fallbackFile, this._basePath, this.forcedLocale]);

  Future<bool> load() async {
    try {
      await _loadCurrentTranslation(this.forcedLocale);
    } catch (e) {
      _printDebugMessage('Error loading translation $e');
      await _loadFallback();
    }
    return true;
  }

  Future _loadCurrentTranslation(final Locale locale) async {
    this.locale = locale != null ? locale : await _findCurrentLocale();
    _printDebugMessage("The current locale is ${this.locale}");
    await _loadFile(_composeFileName());
  }

  Future _loadFallback() async {
    try {
      await _loadFile(_fallbackFile);
    } catch (e) {
      _printDebugMessage('Error loading translation fallback $e');
      decodedMap = Map();
    }
  }

  Future<void> _loadFile(final String fileName) async {
    try {
      await _decodeFile(fileName, 'json', json.decode);
      _printDebugMessage("JSON file loaded for $fileName");
    } on Error catch (_) {
      _printDebugMessage("Unable to load JSON file for $fileName, I'm trying with YAML");
      await _decodeFile(fileName, 'yaml', loadYaml);
    }
  }

  Future<void> _decodeFile(final String fileName, final String extension,
      final Function decodeFunction) async {
    decodedMap = await rootBundle
        .loadString('$_basePath/$fileName.$extension')
        .then((fileContent) => decodeFunction(fileContent));
  }

  Future<Locale> _findCurrentLocale() async {
    final String systemLocale = await _findDeviceLocale();
    _printDebugMessage("The system locale is $systemLocale");
    final List<String> systemLocaleSplitted = systemLocale.split("_");
    final int countryCodeIndex = systemLocaleSplitted.length == 3 ? 2 : 1;
    return Future(() => Locale(
        systemLocaleSplitted[0], systemLocaleSplitted[countryCodeIndex]));
  }

  static String plural(final BuildContext context, final String translationKey,
      final int pluralValue) {
    final FlutterI18n currentInstance = _retrieveCurrentInstance(context);
    final Map<dynamic, dynamic> decodedSubMap =
        _calculateSubmap(currentInstance.decodedMap, translationKey);
    final String correctKey =
        _findCorrectKey(decodedSubMap, translationKey, pluralValue);
    final String parameterName =
        _findParameterName(decodedSubMap[correctKey.split(".").last]);
    return translate(context, correctKey,
        Map.fromIterables([parameterName], [pluralValue.toString()]));
  }

  static String _findCorrectKey(Map<dynamic, dynamic> decodedSubMap,
      String translationKey, final int pluralValue) {
    final List<String> splittedKey = translationKey.split(".");
    translationKey = splittedKey.removeLast();
    List<int> possiblePluralValues = decodedSubMap.keys
        .where((mapKey) => mapKey.startsWith(translationKey))
        .where((mapKey) => mapKey.split("-").length == 2)
        .map((mapKey) => int.tryParse(mapKey.split("-")[1]))
        .where((mapKeyPluralValue) => mapKeyPluralValue != null)
        .where((mapKeyPluralValue) => mapKeyPluralValue <= pluralValue)
        .toList();
    possiblePluralValues.sort();
    final String lastKeyPart =
        "$translationKey-${possiblePluralValues.length > 0 ? possiblePluralValues.last : ''}";
    splittedKey.add(lastKeyPart);
    return splittedKey.join(".");
  }

  static Map<dynamic, dynamic> _calculateSubmap(
      Map<dynamic, dynamic> decodedMap, final String translationKey) {
    final List<String> translationKeySplitted = translationKey.split(".");
    translationKeySplitted.removeLast();
    translationKeySplitted.forEach((listKey) => decodedMap =
        decodedMap != null && decodedMap[listKey] != null
            ? decodedMap[listKey]
            : new Map());
    return decodedMap;
  }

  static String _findParameterName(final String translation) {
    String parameterName = "";
    if (translation != null && _parameterRegexp.hasMatch(translation)) {
      final Match match = _parameterRegexp.firstMatch(translation);
      parameterName = match.groupCount > 0 ? match.group(1) : "";
    }
    return parameterName;
  }

  static Future refresh(
      final BuildContext context, final Locale forcedLocale) async {
    final FlutterI18n currentInstance = _retrieveCurrentInstance(context);
    currentInstance.forcedLocale = forcedLocale;
    await currentInstance._loadCurrentTranslation(forcedLocale);
  }

  static String translate(final BuildContext context, final String key,
      [final Map<String, String> translationParams]) {
    String translation = _translateWithKeyFallback(context, key);
    if (translationParams != null) {
      translation = _replaceParams(translation, translationParams);
    }
    return translation;
  }

  static Locale currentLocale(final BuildContext context) {
    return _retrieveCurrentInstance(context).locale;
  }

  static String _replaceParams(
      String translation, final Map<String, String> translationParams) {
    for (final String paramKey in translationParams.keys) {
      translation = translation.replaceAll(
          new RegExp('{$paramKey}'), translationParams[paramKey]);
    }
    return translation;
  }

  static String _translateWithKeyFallback(
      final BuildContext context, final String key) {
    final Map<dynamic, dynamic> decodedStrings =
        _retrieveCurrentInstance(context).decodedMap;
    String translation = _decodeFromMap(decodedStrings, key);
    if (translation == null) {
      _printDebugMessage("**$key** not found");
      translation = key;
    }
    return translation;
  }

  static FlutterI18n _retrieveCurrentInstance(BuildContext context) {
    return Localizations.of<FlutterI18n>(context, FlutterI18n);
  }

  static String _decodeFromMap(
      Map<dynamic, dynamic> decodedStrings, final String key) {
    final Map<dynamic, dynamic> subMap = _calculateSubmap(decodedStrings, key);
    final String lastKeyPart = key.split(".").last;
    return subMap[lastKeyPart];
  }

  String _composeFileName() {
    return "${locale.languageCode}${_composeCountryCode()}";
  }

  String _composeCountryCode() {
    String countryCode = "";
    if (_useCountryCode && locale.countryCode != null) {
      countryCode = "_${locale.countryCode}";
    }
    return countryCode;
  }

  static void _printDebugMessage(final String message) {
    if(!Foundation.kReleaseMode) {
      print(message);
    }
  }

  Future<String> _findDeviceLocale() async {
    String currentLocale;

    try {
      currentLocale = await Devicelocale.currentLocale;
      print(currentLocale);
    } on PlatformException {
      print("Error obtaining current locale");
    }
    return currentLocale;

  }
}