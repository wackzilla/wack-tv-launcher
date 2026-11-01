/*
 * Wack XP Launcher (FLauncher fork)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/xp/xp_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _refreshEvery = Duration(minutes: 30);
// The TV may still be joining the network when the launcher starts.
const _retryEvery = Duration(minutes: 2);

const _shadow = [Shadow(color: Color(0x99000000), offset: Offset(0, 2), blurRadius: 10)];

/// Current conditions for the location saved on this TV, or a button to set one.
class WeatherPanel extends StatelessWidget
{
  const WeatherPanel({super.key});

  @override
  Widget build(BuildContext context) => Selector<SettingsService, WeatherLocation?>(
    selector: (_, settings) => settings.weatherLocation,
    builder: (context, location, _) => location == null
        ? const _SetLocationButton()
        : _Forecast(key: ValueKey(location), location: location),
  );
}

class _SetLocationButton extends StatelessWidget
{
  const _SetLocationButton();

  @override
  Widget build(BuildContext context) => XpPressable(
    onPressed: () => showWeatherLocationDialog(context),
    builder: (context, focused) {
      final color = focused ? Colors.black87 : Colors.white;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: focused ? Colors.white : ScenicColors.glassStrong,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wb_sunny_outlined, size: 18, color: color),
            const SizedBox(width: 8),
            Text("Set weather location", style: TextStyle(color: color, fontSize: 14)),
          ],
        ),
      );
    },
  );
}

/// Asks for a US ZIP code and saves where it is, on this TV only.
Future<void> showWeatherLocationDialog(BuildContext context) =>
    showXpDialog(context, const _WeatherLocationDialog());

class _WeatherLocationDialog extends StatefulWidget
{
  const _WeatherLocationDialog();

  @override
  State<_WeatherLocationDialog> createState() => _WeatherLocationDialogState();
}

class _WeatherLocationDialogState extends State<_WeatherLocationDialog>
{
  final TextEditingController _zip = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _zip.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (_zip.text.length != 5) {
      setState(() => _error = "Enter a 5 digit ZIP code.");
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final settingsService = context.read<SettingsService>();
    final navigator = Navigator.of(context);
    String? error;
    try {
      final location = await _lookUpZip(_zip.text);
      if (location == null) {
        error = "Couldn't find that ZIP code.";
      }
      else {
        await settingsService.setWeatherLocation(location);
        navigator.pop();
        return;
      }
    }
    catch (lookUpError) {
      debugPrint("ZIP lookup failed: $lookUpError");
      error = "Couldn't look that up. Check the network and try again.";
    }

    if (mounted) {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  // Sits above the middle of the screen to leave room for the on-screen keyboard.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 220),
    child: XpWindow(
      title: "Weather location",
      icon: Icons.wb_sunny_outlined,
      width: 360,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _zip,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(labelText: "ZIP code", errorText: _error),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                XpButton(label: _saving ? "Saving..." : "Save", onPressed: _save),
                const SizedBox(width: 8),
                XpButton(label: "Cancel", onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<WeatherLocation?> _lookUpZip(String zip) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.getUrl(Uri.https("geocoding-api.open-meteo.com", "/v1/search", {
      "name": zip,
      "count": "1",
      "language": "en",
      "format": "json",
      "countryCode": "US",
    }));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException("ZIP lookup returned ${response.statusCode}");
    }

    final Map<String, dynamic> body = jsonDecode(await response.transform(utf8.decoder).join());
    final List<dynamic>? results = body["results"];
    if (results == null || results.isEmpty) {
      return null;
    }

    final Map<String, dynamic> place = results.first;
    return (
      latitude: (place["latitude"] as num).toDouble(),
      longitude: (place["longitude"] as num).toDouble(),
      name: [place["name"], place["admin1"]].whereType<String>().join(", "),
    );
  }
  finally {
    client.close();
  }
}

/// Keeps the last reading if a refresh fails, and shows nothing until there's a first one.
class _Forecast extends StatefulWidget
{
  final WeatherLocation location;

  const _Forecast({super.key, required this.location});

  @override
  State<_Forecast> createState() => _ForecastState();
}

class _ForecastState extends State<_Forecast>
{
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  Timer? _timer;
  _Weather? _weather;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client.close(force: true);
    super.dispose();
  }

  Future<void> _refresh() async {
    _Weather? weather;
    try {
      final request = await _client.getUrl(Uri.https("api.open-meteo.com", "/v1/forecast", {
        "latitude": "${widget.location.latitude}",
        "longitude": "${widget.location.longitude}",
        "current": "temperature_2m,weather_code",
        "daily": "temperature_2m_max,temperature_2m_min",
        "temperature_unit": "fahrenheit",
        "timezone": "auto",
        "forecast_days": "1",
      }));
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        weather = _Weather.fromJson(jsonDecode(await response.transform(utf8.decoder).join()));
      }
      else {
        await response.drain<void>();
      }
    }
    catch (error) {
      debugPrint("Weather failed: $error");
    }

    if (!mounted) {
      return;
    }
    if (weather != null) {
      setState(() => _weather = weather);
    }
    _timer = Timer(_weather == null ? _retryEvery : _refreshEvery, _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    if (weather == null) {
      return const SizedBox.shrink();
    }

    return ScenicDarkBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(weather.icon, color: Colors.white, size: 52, shadows: _shadow),
              const SizedBox(width: 12),
              Text("${weather.temperature}°",
                style: const TextStyle(color: Colors.white, fontSize: 65, height: 1.1, fontWeight: FontWeight.w300, shadows: _shadow),
              ),
            ],
          ),
          Text(weather.condition,
            style: const TextStyle(color: Colors.white, fontSize: 21, shadows: _shadow),
          ),
          const SizedBox(height: 2),
          Text("H ${weather.high}°  L ${weather.low}°  ·  ${widget.location.name}",
            style: const TextStyle(color: Colors.white, fontSize: 17.5, shadows: _shadow),
          ),
        ],
      ),
    );
  }
}

class _Weather
{
  final int temperature;
  final int high;
  final int low;
  final int code;

  _Weather.fromJson(Map<String, dynamic> json) :
    temperature = (json["current"]["temperature_2m"] as num).round(),
    code = (json["current"]["weather_code"] as num).toInt(),
    high = (json["daily"]["temperature_2m_max"][0] as num).round(),
    low = (json["daily"]["temperature_2m_min"][0] as num).round();

  /// WMO weather interpretation codes, as used by Open-Meteo.
  String get condition => switch (code) {
    0 => "Clear",
    1 => "Mostly clear",
    2 => "Partly cloudy",
    3 => "Overcast",
    45 || 48 => "Fog",
    51 || 53 || 55 => "Drizzle",
    56 || 57 => "Freezing drizzle",
    61 || 63 || 65 => "Rain",
    66 || 67 => "Freezing rain",
    71 || 73 || 75 || 77 => "Snow",
    80 || 81 || 82 => "Rain showers",
    85 || 86 => "Snow showers",
    95 || 96 || 99 => "Thunderstorms",
    _ => "",
  };

  IconData get icon => switch (code) {
    0 || 1 => Icons.wb_sunny_outlined,
    2 => Icons.wb_cloudy_outlined,
    3 => Icons.cloud_outlined,
    45 || 48 => Icons.foggy,
    71 || 73 || 75 || 77 || 85 || 86 => Icons.ac_unit,
    95 || 96 || 99 => Icons.thunderstorm_outlined,
    _ => Icons.water_drop_outlined,
  };
}
