// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// -----------------
// Mumbai Deployment
// -----------------


// Old MockMatrix Addresses:
// - 0x58f44400e9B05582c2fA954a5d2622e3EDf918dD;
// - 0xBE6664FC5DcE36F3dA4fc256Faa92930C276F76c;

// ~ Core contracts ~

address constant Mumbai_BalanceBatchReader             = 0xc4b351F7e9597Ba82B3Ad726A573a0e9492413ff;
address constant Mumbai_MockMatrix                     = 0xf4f41647554c43927ae2C3806D03aD864D19A1d9;
address constant Mumbai_USDUSDOracle                   = 0x9e92B33DbF3416Ce2eF8b8d9036A8F84cC30c9b7;
address constant Mumbai_ChainLinkOracle                = 0x077306ED1b3a206C1f226Ad5fa3234ce0A4Fb8CC;
address constant Mumbai_ChainLinkOracleGBP             = 0xb24Ce57c96d27690Ae68aa77656a821d5A53b5eB;
address constant Mumbai_FactoryV2                      = 0x1d5De3D5C8917C4FeF87388E410a73F52FAa7A7C;
address constant Mumbai_CurrencyFeedV2                 = 0xE47B7834fE12c04C900A5776E58743A9133E93e1;
address constant Mumbai_GoldOracleTangibleV2           = 0xA9327c33988DDf00463a531FB8624A3b1f85c81c;
address constant Mumbai_RealtyOracleTangibleV2         = 0x5e0E7A16573fD5B1a5321D60873501484a9b5AD7;
address constant Mumbai_TangibleV3TokenOracle          = 0x6308767381DbC1c9933FfE48bcD72aA85831A73c;
address constant Mumbai_Exchange                       = 0x4465f1BC5B008D4444eb746e649Cddd0c99F5DA4;
address constant Mumbai_SellFeeDistributorV2           = 0xbF7f5f1eeEE2342921860d36a25Be7ECf39a06F6;
address constant Mumbai_TnftDeployerV2                 = 0x07d3A93e8F3359125FFa1eb587D5a9c61B455cE4;
address constant Mumbai_PriceManager                   = 0x04F50c2E4B131531D11FE782c6a64C590e62001F;
address constant Mumbai_RentManagerDeployer            = 0x91B4Cb636B2DD157E5Bda622839359fEa2d42f3F;
address constant Mumbai_TNFTMetadata                   = 0x7CF9EdB9F76E27CaE942bd81beC8bBd920b023DB;
address constant Mumbai_OnSaleTracker                  = 0x8e043D4DC0155755a63f89aB53C29b3a6f34F0dC;
address constant Mumbai_Marketplace                    = 0xeAabDEC8086649D81f006aCBf49214EEe67516d1;
address constant Mumbai_TangibleGoldBarsTnft           = 0xa0ee5F42EffF80e4e9229c090A89aed6c585EaAa;
address constant Mumbai_TangibleREstateTnft            = 0x0d4a53AE894C8E109b55cAD5F840920d46E00B93;
address constant Mumbai_RentManagerTnft                = 0x291fd3A35F2712d14d2f9D678BbA71bd226E7f69;
address constant Mumbai_RWAPriceNotificationDispatcher = 0x3eD35368386f925105A89975FFC8743bcCEd3EcB;
address constant Mumbai_RentNotificationDispatcher     = 0x5aB34991E0695AfdFDBED0Dc97FBeB78C43067Ba;
address constant Mumbai_TangibleProfile                = 0x7aa7D872B335eF8c1f5eB21C8C9Dc4d05Bf3AABF;
address constant Mumbai_TangibleReaderHelper           = 0xbb3833446316f92b1D657146b1fB7529ee130C32;

// ~ Baskets ~

address constant Mumbai_BasketManager = 0x1618efC9867F3Bd7D2bf80ce5f7E6174Fd3bEf96;
address constant Mumbai_Basket1 = 0x8D28AdB25d1EE045eB06BA44EF90B4bD90AF3cB8;

address constant Mumbai_MockVrfCoordinator = 0x1CFd36EcA4D765E858a21dBD9acdCB2A7dC368B7;
address constant Mumbai_BasketVrfConsumer = 0x0527bB4d1AaC36F01933632Ba311d3A36EfE0A33;

address constant Mumbai_BasketImplementation = 0x909Fd75Ce23a7e61787FE2763652935F92116461;
address constant Mumbai_BasketManagerImplementation = 0xBe1d3320E1020910Cd3eb385ADc220e39E355640;

address constant Mumbai_BasketVrfConsumerImplementation = 0x0566eE6aF0cf91fd5b5F6e98D02EcAe1317AD9F0;