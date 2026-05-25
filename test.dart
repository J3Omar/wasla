void main() {
  int? x = 5;
  int? y = null;
  List<int> l = [1, 2, ?x, ?y];
  print(l);
}
