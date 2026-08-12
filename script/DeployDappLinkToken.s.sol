// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DappLinkToken} from "../src/core/contracts/DappLinkToken.sol";
import {CardManager} from "../src/core/contracts/CardManager.sol";
import {LpManager} from "../src/core/contracts/LpManager.sol";

/// @notice Deploys DappLinkToken and all manager contracts using transparent proxies.
/// @dev OpenZeppelin v5 creates one ProxyAdmin for each transparent proxy. Every
///      ProxyAdmin is owned by PROXY_ADMIN_OWNER. Keep that account separate from
///      the business owner/manager accounts.
contract DeployDappLinkTokenScript is Script {
    // keccak256("eip1967.proxy.admin") - 1
    bytes32 private constant ERC1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e019a396cae13b9f8a6016e019a396cae;

    struct TokenConfig {
        address owner;
        address usdt;
        address v2Factory;
        address v2Router;
        address treasureAddress;
        address marking;
        address operator;
        address caller;
    }

    function run() external returns (DappLinkToken token, CardManager cardManager, LpManager lpManager) {
        address proxyAdminOwner = vm.envAddress("PROXY_ADMIN_OWNER");
        TokenConfig memory tokenConfig = _tokenConfig();

        vm.startBroadcast();

        token = _deployToken(proxyAdminOwner, tokenConfig);
        cardManager = _deployCardManager(proxyAdminOwner, address(token));
        lpManager = _deployLpManager(proxyAdminOwner, address(token), tokenConfig.usdt, tokenConfig.v2Router);

        vm.stopBroadcast();

        _logDeployment("DappLinkToken", address(token));
        _logDeployment("CardManager", address(cardManager));
        _logDeployment("LpManager", address(lpManager));
    }

    function _deployToken(address proxyAdminOwner, TokenConfig memory config) private returns (DappLinkToken token) {
        DappLinkToken implementation = new DappLinkToken();
        bytes memory initializationData = abi.encodeCall(
            DappLinkToken.initialize,
            (
                config.owner,
                config.usdt,
                config.v2Factory,
                config.v2Router,
                config.treasureAddress,
                config.marking,
                config.operator,
                config.caller
            )
        );
        token = DappLinkToken(
            address(new TransparentUpgradeableProxy(address(implementation), proxyAdminOwner, initializationData))
        );
    }

    function _deployCardManager(address proxyAdminOwner, address underlyingToken)
        private
        returns (CardManager cardManager)
    {
        CardManager implementation = new CardManager();
        bytes memory initializationData = abi.encodeCall(
            CardManager.initialize,
            (
                vm.envAddress("CARD_OWNER"),
                vm.envAddress("CARD_MANAGER"),
                vm.envAddress("CARD_CONTRACT_CALLER"),
                underlyingToken,
                vm.envString("CARD_NFT_JSON")
            )
        );
        cardManager = CardManager(
            payable(address(
                    new TransparentUpgradeableProxy(address(implementation), proxyAdminOwner, initializationData)
                ))
        );
    }

    function _deployLpManager(address proxyAdminOwner, address underlyingToken, address usdt, address v2Router)
        private
        returns (LpManager lpManager)
    {
        LpManager implementation = new LpManager();
        bytes memory initializationData = abi.encodeCall(
            LpManager.initialize,
            (vm.envAddress("LP_OWNER"), vm.envAddress("LP_MANAGER"), underlyingToken, usdt, v2Router)
        );
        lpManager = LpManager(
            payable(address(
                    new TransparentUpgradeableProxy(address(implementation), proxyAdminOwner, initializationData)
                ))
        );
    }

    function _tokenConfig() private view returns (TokenConfig memory config) {
        config = TokenConfig({
            owner: vm.envAddress("TOKEN_OWNER"),
            usdt: vm.envAddress("USDT"),
            v2Factory: vm.envAddress("V2_FACTORY"),
            v2Router: vm.envAddress("V2_ROUTER"),
            treasureAddress: vm.envAddress("TREASURE_ADDRESS"),
            marking: vm.envAddress("MARKING"),
            operator: vm.envAddress("OPERATOR"),
            caller: vm.envAddress("CALLER")
        });
    }

    function _logDeployment(string memory name, address proxy) private view {
        address proxyAdmin = address(uint160(uint256(vm.load(proxy, ERC1967_ADMIN_SLOT))));
        console2.log(string.concat(name, " proxy:"), proxy);
        console2.log(string.concat(name, " ProxyAdmin:"), proxyAdmin);
    }
}
