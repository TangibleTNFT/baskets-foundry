// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

// -----------------
// Mumbai Deployment
// -----------------


// Old MockMatrix Addresses:
// - 0x58f44400e9B05582c2fA954a5d2622e3EDf918dD;
// - 0xBE6664FC5DcE36F3dA4fc256Faa92930C276F76c;

// ~ Core contracts ~

address constant Mumbai_BalanceBatchReader             = 0x97cF8d8e194C5A6E77c0b469C070df84c71e637b;
address constant Mumbai_MockMatrix                     = 0x1Cd48C464e9E9e8E3676fCF5339fF44C91D15B3B;
address constant Mumbai_USDUSDOracle                   = 0xc0026BD217e6dAB015Ab92910d6e563Ec0BEdcB0;
address constant Mumbai_ChainLinkOracle                = 0x638265de853bC8aA0c5D45eEF82cb9192836f12E;
address constant Mumbai_ChainLinkOracleGBP             = 0xfdDB736F020275e129f21bE1314044fEfBBcF6e4;
address constant Mumbai_FactoryV2                      = 0x9126c87E590818dAf9a4B30C75d44B4000783B17;
address constant Mumbai_CurrencyFeedV2                 = 0xE5B0699DfB8253eD8e82AC43e8a3E3C0fe8AAfF5;
address constant Mumbai_GoldOracleTangibleV2           = 0x1DeB16e9f722AA1355cBcDC4028A269C2102012d;
address constant Mumbai_RealtyOracleTangibleV2         = 0xB504c09B8D86BCFDB91170A54b20c968F43C9f07;
address constant Mumbai_TangibleV3TokenOracle          = 0xAE1823a60fFCc442069bD834116e82b066f32CAA;
address constant Mumbai_Exchange                       = 0x874b03Bf7a482c3Ef1F67f315EF6daB91953419e;
address constant Mumbai_SellFeeDistributorV2           = 0x9acdba8Fa4B95cC4fB1180C966AC8235Cc2f3c79;
address constant Mumbai_TnftDeployerV2                 = 0xE9e20d81901a3FfC3e7Fe7E81921E93DfC27bdf1;
address constant Mumbai_PriceManager                   = 0x6Aa97041244BA0E1c8b8D0Fa04542cfD0b5379cD;
address constant Mumbai_RentManagerDeployer            = 0xD23fE1403340df0389d3bbbcFBE9d9C8DB1A5be5;
address constant Mumbai_TNFTMetadata                   = 0x7179DB2712583bdb1889625DCF4bf6808c55248c;
address constant Mumbai_OnSaleTracker                  = 0x39eD4fA2D8a59C35D463D7810594Eb0D9a2f1289;
address constant Mumbai_Marketplace                    = 0x5Cf739Ae13f9b77492e4Cc6B5194AE464f8b3865;
address constant Mumbai_TangibleGoldBarsTnft           = 0x3B78997bCEf54E8c8684214e04277cef4a3B6E91;
address constant Mumbai_TangibleREstateTnft            = 0xe3A81350e42DF609C52b94410FE2c25A7f7e6B31;
address constant Mumbai_RentManagerTnft                = 0xA49b220b083b4510b32219BF8D3ea4A8888d4bEB;
address constant Mumbai_RWAPriceNotificationDispatcher = 0xDDFD601C2fD50479EC829B9dF3b4fd7aDb0E8A2F;
address constant Mumbai_RentNotificationDispatcher     = 0x1D967a4AE4117D8DBDBB73059025129C6505709a;
address constant Mumbai_TangibleProfile                = 0x74268E0655890E3cB66e60DE9fF48161e96f6094;
address constant Mumbai_TangibleReaderHelper           = 0xD1840163094C94e9EA3d0DeCbA17A0c7b01dCd3e;

// ~ Baskets ~

// proxies
address constant Mumbai_BasketManager          = 0x1e44E0a4B8596E47E291f868A0485864AC7eE869;
address constant Mumbai_BasketVrfConsumer      = 0x192ab3Dfee4e087C4F5a5cE54F3053fe4D0C277D;
// implementation
address constant Mumbai_BasketManager_base     = 0x1FA8f797A5D6a56aee856850aa701157EA53f57E;
address constant Mumbai_BasketVrfConsumer_base = 0x36b6240FD63D5A4fb095AbF7cC8476659C76071C;
address constant Mumbai_Basket_base            = 0x86892455EB3F49307607aA006c15D11Af0ac7aA4;
// mock
address constant Mumbai_MockVrfCoordinator     = 0x19d3746C662973E17C2a8658D958a977fbfdeb29;

// ~ Deployed Baskets ~

address constant Mumbai_Basket_1 = address(0); // TODO: SET