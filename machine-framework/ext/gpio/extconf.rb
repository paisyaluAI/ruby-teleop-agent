require 'mkmf'

# C++17規格の指定
$CXXFLAGS << ' -std=c++17'

# libgpiod-dev に含まれる C++(libgpiodcxx) および C(libgpiod) ライブラリを直接リンク指定
$libs << ' -lgpiodcxx -lgpiod'

create_makefile('libgpiod_ext')
