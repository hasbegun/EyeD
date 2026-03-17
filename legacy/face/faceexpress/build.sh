BUILD_DIR=build
RESULT_DIR=result
JAFFE_DIR=~/devel/datasets/jaffe

if [ ! -d $BUILD_DIR ]; then
  rm -rf $BUILD_DIR
  mkdir $BUILD_DIR $RESULT_DIR
fi

cd $BUILD_DIR
cmake .. && make

if [ ! -f face_comp.sh ]; then
  cat <<-EOF > face_comp.sh
./facial_components -src $JAFFE_DIR -dest $RESULT_DIR
EOF
fi
chmod 755 ./face_comp.sh

if [ ! -f feature_ext.sh ]; then
  cat <<-EOF > feature_ext.sh
./feature_extraction -feature surf -src $RESULT_DIR -dest $RESULT_DIR
EOF
fi
chmod 755 ./feature_ext.sh

if [ ! -f train_algo.sh ]; then
  cat <<-EOF > train_algo.sh
./train -algo svm -src $RESULT_DIR/surf_features.yml -dest $RESULT_DIR
EOF
fi
chmod 755 ./train_algo.sh
