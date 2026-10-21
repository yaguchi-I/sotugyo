import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  bool isCalendarView = true;
  File? _image;

  Future<void> _openCamera() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('家計簿'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => isCalendarView = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isCalendarView ? Colors.blue : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                'カレンダー',
                                style: TextStyle(
                                  color: isCalendarView ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => isCalendarView = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !isCalendarView ? Colors.blue : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '履歴一覧',
                                style: TextStyle(
                                  color: !isCalendarView ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: isCalendarView ? _buildCalendar() : _buildList(),
              ),
            ],
          ),
          Positioned(
            left: 16,
            bottom: 110,
            child: FloatingActionButton(
              heroTag: 'camera_btn',
              onPressed: _openCamera,
              backgroundColor: Colors.white,
              shape: const CircleBorder(),
              child: const Icon(Icons.camera_alt, color: Colors.black),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 110,
            child: FloatingActionButton(
              heroTag: 'ai_btn',
              onPressed: () {},
              backgroundColor: Colors.white,
              shape: const CircleBorder(),
              child: const Text('AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return GridView.builder(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 180.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.6,
      ),
      itemCount: 31,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              Text('${index + 1}'),
              const Spacer(),
              if (index % 3 == 0)
                const Text(
                  '¥8000',
                  style: TextStyle(fontSize: 10, color: Colors.red),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 180.0),
      itemCount: 10,
      itemBuilder: (context, index) {
        return ListTile(
          title: const Text('食費'),
          subtitle: Text('10月${index + 1}日'),
          trailing: const Text('¥2,500', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        );
      },
    );
  }
}