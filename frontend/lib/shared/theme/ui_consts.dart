import 'package:flutter/material.dart';

const SizedBox gap4 = SizedBox(height: 4);
const SizedBox gap6 = SizedBox(height: 6);
const SizedBox gap8 = SizedBox(height: 8);
const SizedBox gap10 = SizedBox(height: 10);
const SizedBox gap12 = SizedBox(height: 12);
const SizedBox gap16 = SizedBox(height: 16);
const SizedBox gap20 = SizedBox(height: 20);
const SizedBox gap24 = SizedBox(height: 24);

const EdgeInsets p8 = EdgeInsets.all(8);
const EdgeInsets p12 = EdgeInsets.all(12);
const EdgeInsets p16 = EdgeInsets.all(16);
const EdgeInsets p20 = EdgeInsets.all(20);
const EdgeInsets px16 = EdgeInsets.symmetric(horizontal: 16);
const EdgeInsets py12 = EdgeInsets.symmetric(vertical: 12);

const Radius r12 = Radius.circular(12);
const BorderRadius br12 = BorderRadius.all(r12);
const BorderRadius br16 = BorderRadius.all(Radius.circular(16));

const Color kBrandTurquoise = Color(0xFF63C7D6);
const Color kBrandAzure = Color(0xFF7AA8F7);
const Color kBrandLilac = Color(0xFFB58CFF);

const LinearGradient kBrandPrimaryGradient = LinearGradient(
  colors: [kBrandTurquoise, kBrandLilac],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kBrandVibrantGradient = LinearGradient(
  colors: [kBrandTurquoise, kBrandAzure, kBrandLilac],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kBrandBluePurpleGradient = LinearGradient(
  colors: [kBrandAzure, kBrandLilac],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
