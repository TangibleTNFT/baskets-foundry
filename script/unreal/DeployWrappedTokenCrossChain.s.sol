// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Script.sol";
import {DeployUtility} from "../DeployUtility.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";
import { WrappedBasketToken } from "../../src/wrapped/WrappedBasketToken.sol";
import { IBasket } from "../../src/interfaces/IBasket.sol";
import { BasketManager } from "../../src/BasketManager.sol";
import { CurrencyCalculator } from "../../src/CurrencyCalculator.sol";
import { BasketsVrfConsumer } from "../../src/BasketsVrfConsumer.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";
import "../utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/unreal/DeployWrappedTokenCrossChain.s.sol:DeployWrappedTokenCrossChain --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually (Base, Optimism, Polygon, BSC):
    export ETHERSCAN_API_KEY="<API_KEY>"
    forge verify-contract <CONTRACT_ADDRESS> --chain-id <CHAIN_ID> --watch src/wrapped/WrappedBasketToken.sol:WrappedBasketToken \
    --verifier etherscan --constructor-args $(cast abi-encode "constructor(address, address)" <LOCAL_LZ_ADDRESS> <BASKET>)
*/

/**
 * @title DeployWrappedTokenCrossChain
 * @author Chase Brown
 * @notice This script deploys a new instance of a wrapped baskets vault token to the Unreal Testnet.
 */
contract DeployWrappedTokenCrossChain is DeployUtility {

    // ~ Script Configure ~

    struct NetworkData {
        string chainName;
        string rpc_url;
        address lz_endpoint;
        uint16 chainId;
        address basket;
        address tokenAddress;
    }

    NetworkData[] internal allChains;

    address constant public BASKET = 0x8bBE2FE226a5d1432ae242B63EFC79c1787D0cF2; // TODO
    string constant public NAME = "Wrapped UKRE"; // TODO
    string constant public SYMBOL = "wUKRE"; // TODO

    address immutable public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        _setup("wUKRE.testnet.deployment");// TODO

        allChains.push(NetworkData(
            {
                chainName: "unreal", 
                rpc_url: vm.envString("UNREAL_RPC_URL"), 
                lz_endpoint: UNREAL_LZ_ENDPOINT_V1, 
                chainId: UNREAL_LZ_CHAIN_ID_V1,
                basket: BASKET,
                tokenAddress: address(0)
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "sepolia", 
                rpc_url: vm.envString("SEPOLIA_RPC_URL"), 
                lz_endpoint: SEPOLIA_LZ_ENDPOINT_V1, 
                chainId: SEPOLIA_LZ_CHAIN_ID_V1, 
                basket: address(0),
                tokenAddress: address(0)
            }
        ));
    }

    function run() public {

        uint256 len = allChains.length;
        for (uint256 i; i < len; ++i) {
            if (allChains[i].tokenAddress == address(0)) {

                vm.createSelectFork(allChains[i].rpc_url);
                vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

                address wrappedBasketTokenAddress = _deployWrappedBasketToken(allChains[i].lz_endpoint, allChains[i].basket);

                allChains[i].tokenAddress = wrappedBasketTokenAddress;
                WrappedBasketToken wrappedBasketToken = WrappedBasketToken(wrappedBasketTokenAddress);

                // set trusted remote address on all other chains for each token.
                for (uint256 j; j < len; ++j) {
                    if (i != j) {
                        if (
                            !wrappedBasketToken.isTrustedRemote(
                                allChains[j].chainId, abi.encodePacked(wrappedBasketTokenAddress, wrappedBasketTokenAddress)
                            )
                        ) {
                            wrappedBasketToken.setTrustedRemoteAddress(
                                allChains[j].chainId, abi.encodePacked(wrappedBasketTokenAddress)
                            );
                        }
                    }
                }

                // save wrappedBasketToken addresses to appropriate JSON
                _saveDeploymentAddress(allChains[i].chainName, SYMBOL, wrappedBasketTokenAddress);
                vm.stopBroadcast();
            }
        }
    }

    /**
     * @dev This method is in charge of deploying and upgrading wrappedToken on any chain.
     * This method will perform the following steps:
     *    - Compute the wrappedToken implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the wrappedToken address computed,
     *      it will upgrade that proxy.
     */
    function _deployWrappedBasketToken(address layerZeroEndpoint, address basket) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(WrappedBasketToken).creationCode);
        address wrappedTokenAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(layerZeroEndpoint, basket)))
        );

        WrappedBasketToken wrappedToken;

        if (_isDeployed(wrappedTokenAddress)) {
            console.log("wrappedToken is already deployed to %s", wrappedTokenAddress);
            wrappedToken = WrappedBasketToken(wrappedTokenAddress);
        } else {
            wrappedToken = new WrappedBasketToken{salt: _SALT}(layerZeroEndpoint, basket);
            assert(wrappedTokenAddress == address(wrappedToken));
            console.log("wrappedToken deployed to %s", wrappedTokenAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            WrappedBasketToken.initialize.selector,
            DEPLOYER_ADDRESS,
            NAME,
            SYMBOL
        );

        proxyAddress = _deployProxy("wrappedBasketToken", address(wrappedToken), init);
    }
}