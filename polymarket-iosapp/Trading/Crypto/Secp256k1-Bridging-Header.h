//
//  Secp256k1-Bridging-Header.h
//  polymarket-iosapp
//
//  アプリに同梱した libsecp256k1（bitcoin-core/secp256k1 v0.7.0, MIT）を Swift から使うためのヘッダ。
//  recovery モジュールはビルド設定 GCC_PREPROCESSOR_DEFINITIONS の ENABLE_MODULE_RECOVERY=1 で有効化している。
//

#include "libsecp256k1/include/secp256k1.h"
#include "libsecp256k1/include/secp256k1_recovery.h"
