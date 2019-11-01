import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite/tflite.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

void main() {
  runApp(MyApp());
}

const String ssd = "SSD MobileNet";
const String yolo = "Tiny YOLOv2";

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TfliteHome(),
      title: "Image Recognizer",
    );
  }
}

class TfliteHome extends StatefulWidget {
  @override
  _TfliteHomeState createState() => _TfliteHomeState();
}

class _TfliteHomeState extends State<TfliteHome> {
  String _model = ssd;
  File _image;

  double _imageWidth;
  double _imageHeight;
  bool _busy = false;
  bool recognized = false;

  List _recognitions = [];
  List detectedObjects = [];

  @override
  void initState() {
    super.initState();
    _busy = true;

    loadModel().then((val) {
      setState(() {
        _busy = false;
      });
    });
  }

  loadModel() async {
    Tflite.close();
    try {
      String res;
      if (_model == yolo) {
        res = await Tflite.loadModel(
          model: "assets/tflite/yolov2_tiny.tflite",
          labels: "assets/tflite/yolov2_tiny.txt",
        );
      } else {
        res = await Tflite.loadModel(
          model: "assets/tflite/ssd_mobilenet.tflite",
          labels: "assets/tflite/ssd_mobilenet.txt",
        );
      }
      print(res);
    } on PlatformException {
      print("Failed to load the model");
    }
  }

  selectFromImagePicker() async {
    var image = await ImagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() {
      _busy = true;
    });
    await predictImage(image);
  }

  predictImage(File image) async {
    if (image == null) return;

    if (_model == yolo) {
      await yolov2Tiny(image);
    } else {
      await ssdMobileNet(image);
    }

    FileImage(image)
        .resolve(ImageConfiguration())
        .addListener((ImageStreamListener((ImageInfo info, bool _) {
          setState(() {
            _imageWidth = info.image.width.toDouble();
            _imageHeight = info.image.height.toDouble();
          });
        })));

    setState(() {
      _image = image;
      _busy = false;
    });
  }

  yolov2Tiny(File image) async {
    var recognitions = await Tflite.detectObjectOnImage(
        path: image.path,
        model: "YOLO",
        threshold: 0.3,
        imageMean: 0.0,
        imageStd: 255.0,
        numResultsPerClass: 1);

    setState(() {
      _recognitions = recognitions;
      detectedObjects.addAll(recognitions);
      recognized = true;
    });
  }

  ssdMobileNet(File image) async {
    var recognitions = await Tflite.detectObjectOnImage(
        path: image.path, numResultsPerClass: 1);

    setState(() {
      _recognitions = recognitions;
      detectedObjects.addAll(recognitions);
      recognized = true;
    });
  }

  List<Widget> renderBoxes(Size screen) {
    if (_recognitions == null) return [];
    if (_imageWidth == null || _imageHeight == null) return [];

    double factorX = screen.width;
    double factorY = _imageHeight / _imageHeight * screen.width;

    Color blue = Colors.red;
    print(_recognitions);
    return _recognitions.where((re) => re['confidenceInClass'] > 0.6).map((re) {
      return Positioned(
        left: re["rect"]["x"] * factorX,
        top: re["rect"]["y"] * factorY,
        width: re["rect"]["w"] * factorX,
        height: re["rect"]["h"] * factorY,
        child: Container(
          decoration: BoxDecoration(
              border: Border.all(
            color: blue,
            width: 3,
          )),
          child: Text(
            "${re["detectedClass"]} ${(re["confidenceInClass"] * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              background: Paint()..color = blue,
              color: Colors.white,
              fontSize: 18,
            ),
          ),
        ),
      );
    }).toList();
  }

  Future<Null> clearObjects() async {
    setState(() {
      recognized = false;
      detectedObjects.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;

    List<Widget> stackChildren = [];

    stackChildren.add(_image == null
        ? Center(child: Text("No Image Selected"))
        : Positioned(
            top: 0.0,
            left: 0.0,
            width: size.width,
            child: Image.file(_image),
          ));

    stackChildren.addAll(renderBoxes(size));

    if (_busy) {
      stackChildren.add(Center(
        child: CircularProgressIndicator(),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("iRecog"),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.image),
        tooltip: "Pick Image from gallery",
        onPressed: () async {
          await selectFromImagePicker();
          if (recognized) {
            await showModalBottomSheet(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16.0),
                      topRight: Radius.circular(16.0)),
                ),
                context: context,
                builder: (ctx) {
                  List higherConfidence = detectedObjects
                      .where((object) => object['confidenceInClass'] > 0.6)
                      .toList();
                  List lowerConfidence = detectedObjects
                      .where((object) => object['confidenceInClass'] <= 0.6)
                      .toList();
                  return ListView.separated(
                    separatorBuilder: (BuildContext _, int pos) {
                      return Divider();
                    },
                    itemCount: higherConfidence.length > 0
                        ? higherConfidence.length
                        : lowerConfidence.length,
                    itemBuilder: (BuildContext _, int pos) {
                      return Padding(
                        padding: EdgeInsets.all(4.0),
                        child: ListTile(
                          title: Text(higherConfidence.length > 0
                              ? higherConfidence[pos]['detectedClass']
                              : lowerConfidence[pos]['detectedClass']),
                          trailing: Text(
                              "${higherConfidence.length > 0 ? higherConfidence[pos]['confidenceInClass'] * 100 : lowerConfidence[pos]['confidenceInClass'] * 100} %"),
                        ),
                      );
                    },
                  );
                });
            await clearObjects();
          }
        },
      ),
      body: Stack(
        children: stackChildren,
      ),
    );
  }
}
