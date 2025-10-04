/// Sensor Selector Widget
/// 
/// Dropdown to select a sensor for detailed statistics

import 'package:flutter/material.dart';
import '../../core/api/api_models.dart';

class SensorSelector extends StatelessWidget {
  final List<Sensor> sensors;
  final String? selectedSensorId;
  final Function(String sensorId) onSensorChanged;

  const SensorSelector({
    Key? key,
    required this.sensors,
    this.selectedSensorId,
    required this.onSensorChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Sensor',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedSensorId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.sensors),
                hintText: 'Choose a sensor...',
              ),
              items: sensors.map((sensor) {
                return DropdownMenuItem<String>(
                  value: sensor.id,
                  child: Text(
                    sensor.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  onSensorChanged(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
