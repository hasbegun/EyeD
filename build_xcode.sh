BLD=build
rm -rf $BLD
mkdir $BLD
cd $BLD

OCV=/usr/local/opt/opencv3
QT5=/usr/local/qt/5.7/clang_64
TBB=/usr/local/opt/tbb
TBB_INC=${TBB}/include
TBB_LIB=${TBB}/lib

#cmake -D CMAKE_PREFIX_PATH=$QT -D OpenCV_DIR=$OCV -G $TARGET ..

#cmake -D CMAKE_PREFIX_PATH=${QT5} -D OpenCV_DIR=${OCV} \
#-D TBB_INCLUDE_DIR=${TBB_INC} -D TBB_LIBRARY=${TBB_LIB} ..

cmake -D CMAKE_PREFIX_PATH=${QT5} -D OpenCV_DIR=${OCV} -D TBB_DIR=${TBB} ..

#cmake -D CMAKE_PREFIX_PATH=${QT5}:${TBB} -D OpenCV_DIR=${OCV} ..
