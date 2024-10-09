// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Script.sol";
import {DeployUtility} from "../DeployUtility.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { WrappedBasketToken } from "../../src/wrapped/WrappedBasketToken.sol";
import { WrappedBasketTokenSatellite } from "../../src/wrapped/WrappedBasketTokenSatellite.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";
import "../utils/Constants.sol";

/** 
    @dev To run: 
    forge script script/wrapped/DeployWrappedTokenCrossChain.s.sol:DeployWrappedTokenCrossChain --broadcast --legacy \
    --gas-estimate-multiplier 500 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify Proxy manually (Etherscan):
    export ETHERSCAN_API_KEY="<API_KEY>"
    forge verify-contract <CONTRACT_ADDRESS> --chain-id <CHAIN_ID> --watch \
    lib/tangible-foundation-contracts/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" <EMPTY_UUPS> 0x) --verifier etherscan

    @dev To verify WrappedBasketSatellite manually (Etherscan):
    export ETHERSCAN_API_KEY="<API_KEY>"
    forge verify-contract <CONTRACT_ADDRESS> --chain-id <CHAIN_ID> --watch \
    src/wrapped/WrappedBasketTokenSatellite.sol:WrappedBasketTokenSatellite --constructor-args \
    $(cast abi-encode "constructor(address)" <LZ_ENDPOINT_ADDRESS>) --verifier etherscan
*/

/**
 * @title DeployWrappedTokenCrossChain
 * @author Chase Brown
 * @notice This script deploys a new instance of a wrapped baskets vault token to numerous mainnet chains.
 */
contract DeployWrappedTokenCrossChain is DeployUtility {

    // ~ Script Configure ~

    struct NetworkData {
        string chainName;
        string rpc_url;
        address lz_endpoint;
        uint16 chainId;
        address basket;
        bool mainChain;
    }

    NetworkData[] internal allChains;

    address constant public BASKET = 0x835d3E1C0aA079C6164AAd21DCb23E60eb71AF48; // TODO
    string constant public NAME = "Wrapped UKRE"; // TODO
    string constant public SYMBOL = "wUKRE"; // TODO

    address immutable public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {
        _setup("wUKRE.mainnet.deployment");// TODO

        allChains.push(NetworkData(
            {
                chainName: "real", 
                rpc_url: vm.envString("REAL_RPC_URL"), 
                lz_endpoint: REAL_LZ_ENDPOINT_V1, 
                chainId: REAL_LZ_CHAIN_ID_V1,
                basket: BASKET,
                mainChain: true
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "arbitrum", 
                rpc_url: vm.envString("ARB_RPC_URL"), 
                lz_endpoint: ARB_LZ_ENDPOINT_V1, 
                chainId: ARB_LZ_CHAIN_ID_V1,
                basket: address(0),
                mainChain: false
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "optimism", 
                rpc_url: vm.envString("OPTIMISM_RPC_URL"), 
                lz_endpoint: OPTIMISM_LZ_ENDPOINT_V1, 
                chainId: OPTIMISM_LZ_CHAIN_ID_V1,
                basket: address(0),
                mainChain: false
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "base", 
                rpc_url: vm.envString("BASE_RPC_URL"), 
                lz_endpoint: BASE_LZ_ENDPOINT_V1, 
                chainId: BASE_LZ_CHAIN_ID_V1,
                basket: address(0),
                mainChain: false
            }
        ));
        allChains.push(NetworkData(
            {
                chainName: "scroll", 
                rpc_url: vm.envString("SCROLL_RPC_URL"), 
                lz_endpoint: SCROLL_LZ_ENDPOINT_V1, 
                chainId: SCROLL_LZ_CHAIN_ID_V1,
                basket: address(0),
                mainChain: false
            }
        ));
    }

    function run() public {

        uint256 len = allChains.length;
        for (uint256 i; i < len; ++i) {

            vm.createSelectFork(allChains[i].rpc_url);
            vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

            address wrappedBasketTokenAddress;
            if (allChains[i].mainChain) {
                address _basket = allChains[i].basket;
                require(_basket != address(0), "basket == address(0)");
                wrappedBasketTokenAddress = _deployWrappedBasketToken(allChains[i].lz_endpoint, _basket);
            }
            else {
                wrappedBasketTokenAddress = _deployWrappedBasketTokenForSatellite(allChains[i].lz_endpoint);
            }

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

    /**
     * @dev This method is in charge of deploying and upgrading wrappedToken on a satellite chain.
     * This method will perform the following steps:
     *    - Compute the wrappedToken implementation address
     *    - If this address is not deployed, deploy new implementation
     *    - Computes the proxy address. If implementation of that proxy is NOT equal to the wrappedToken address computed,
     *      it will upgrade that proxy.
     */
    function _deployWrappedBasketTokenForSatellite(address layerZeroEndpoint) internal returns (address proxyAddress) {
        bytes memory bytecode = abi.encodePacked(type(WrappedBasketTokenSatellite).creationCode);
        address wrappedTokenAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(layerZeroEndpoint)))
        );

        WrappedBasketTokenSatellite wrappedToken;

        if (_isDeployed(wrappedTokenAddress)) {
            console.log("wrappedTokenSatellite is already deployed to %s", wrappedTokenAddress);
            wrappedToken = WrappedBasketTokenSatellite(wrappedTokenAddress);
        } else {
            wrappedToken = new WrappedBasketTokenSatellite{salt: _SALT}(layerZeroEndpoint);
            assert(wrappedTokenAddress == address(wrappedToken));
            console.log("wrappedTokensatellite deployed to %s", wrappedTokenAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            WrappedBasketTokenSatellite.initialize.selector,
            DEPLOYER_ADDRESS,
            NAME,
            SYMBOL
        );

        proxyAddress = _deployProxy("wrappedBasketToken", address(wrappedToken), init);
    }
}