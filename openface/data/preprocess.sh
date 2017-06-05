p=6
raw_path=./working_faces
aligned_path=./working_faces/aligned
for N in {1..$p}; do ../util/align-dlib.py $raw_path align outerEyesAndNose $aligned_path --size 96 --verbose & done
