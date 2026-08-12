// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import {LpManager} from "../src/core/contracts/LpManager.sol";

contract LpMockERC20 is ERC20 {
    constructor(string memory tokenName, string memory tokenSymbol) ERC20(tokenName, tokenSymbol) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockPancakeRouter {
    address public tokenA;
    address public tokenB;
    uint256 public amountADesired;
    uint256 public amountBDesired;
    address public liquidityRecipient;

    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        tokenA = _tokenA;
        tokenB = _tokenB;
        amountADesired = _amountADesired;
        amountBDesired = _amountBDesired;
        liquidityRecipient = to;
        ERC20(_tokenA).transferFrom(msg.sender, address(this), _amountADesired);
        ERC20(_tokenB).transferFrom(msg.sender, address(this), _amountBDesired);
        return (_amountADesired, _amountBDesired, _amountADesired + _amountBDesired);
    }
}

contract LpManagerTest is Test {
    LpManager internal lpManager;
    LpMockERC20 internal underlyingToken;
    LpMockERC20 internal usdt;
    MockPancakeRouter internal router;

    address internal owner = makeAddr("owner");
    address internal manager = makeAddr("manager");
    address internal authorizedCaller = makeAddr("authorizedCaller");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        underlyingToken = new LpMockERC20("Underlying", "UND");
        usdt = new LpMockERC20("USDT", "USDT");
        router = new MockPancakeRouter();
        LpManager implementation = new LpManager();
        bytes memory initData = abi.encodeCall(
            LpManager.initialize, (owner, manager, address(underlyingToken), address(usdt), address(router))
        );
        lpManager = LpManager(payable(address(new ERC1967Proxy(address(implementation), initData))));
    }

    function testInitializeSetsConfiguration() public view {
        assertEq(lpManager.owner(), owner);
        assertEq(lpManager.manager(), manager);
        assertEq(lpManager.underlyingToken(), address(underlyingToken));
        assertEq(lpManager.USDT(), address(usdt));
        assertEq(lpManager.v2Router(), address(router));
    }

    function testInitializeRejectsZeroRouterAndImplementationReinitialization() public {
        LpManager implementation = new LpManager();
        vm.expectRevert();
        implementation.initialize(owner, manager, address(underlyingToken), address(usdt), address(router));

        vm.expectRevert("LpManager: _v2Router cannot be zero address");
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(LpManager.initialize, (owner, manager, address(underlyingToken), address(usdt), address(0)))
        );
    }

    function testManagerCanAddAndRemoveAuthorizedCaller() public {
        vm.prank(manager);
        lpManager.addAuthorizedCaller(authorizedCaller);
        address[] memory callers = lpManager.getAuthorizedCallers();
        assertEq(callers.length, 1);
        assertEq(callers[0], authorizedCaller);

        vm.prank(manager);
        lpManager.removeAuthorizedCaller(authorizedCaller);
        assertEq(lpManager.getAuthorizedCallers().length, 0);
    }

    function testOnlyManagerCanManageAuthorizedCallers() public {
        vm.expectRevert("onlyManager");
        lpManager.addAuthorizedCaller(authorizedCaller);
        vm.expectRevert("onlyManager");
        lpManager.removeAuthorizedCaller(authorizedCaller);
    }

    function testOwnerCanSetManager() public {
        address newManager = makeAddr("newManager");
        vm.prank(owner);
        lpManager.setManager(newManager);
        assertEq(lpManager.manager(), newManager);
    }

    function testSetManagerRejectsUnauthorizedAndZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, recipient));
        vm.prank(recipient);
        lpManager.setManager(recipient);

        vm.expectRevert("manager cannot be zero address");
        vm.prank(owner);
        lpManager.setManager(address(0));
    }

    function testManagerCanWithdrawUnderlyingToken() public {
        underlyingToken.mint(address(lpManager), 100 ether);
        vm.prank(manager);
        lpManager.withdraw(recipient, 40 ether);
        assertEq(underlyingToken.balanceOf(recipient), 40 ether);
        assertEq(underlyingToken.balanceOf(address(lpManager)), 60 ether);
    }

    function testWithdrawChecksRoleAndBalance() public {
        vm.expectRevert("onlyManager");
        lpManager.withdraw(recipient, 1);

        vm.expectRevert("withdraw amount more token balance in this contracts");
        vm.prank(manager);
        lpManager.withdraw(recipient, 1);
    }

    function testAuthorizedCallerCanAddLiquidity() public {
        underlyingToken.mint(address(lpManager), 70 ether);
        usdt.mint(address(lpManager), 30 ether);
        vm.prank(manager);
        lpManager.addAuthorizedCaller(authorizedCaller);

        vm.prank(authorizedCaller);
        lpManager.addLiquidity(70 ether, 30 ether, recipient);

        assertEq(router.tokenA(), address(usdt));
        assertEq(router.tokenB(), address(underlyingToken));
        assertEq(router.amountADesired(), 30 ether);
        assertEq(router.amountBDesired(), 70 ether);
        assertEq(router.liquidityRecipient(), recipient);
        assertEq(usdt.balanceOf(address(router)), 30 ether);
        assertEq(underlyingToken.balanceOf(address(router)), 70 ether);
        assertEq(usdt.allowance(address(lpManager), address(router)), 0);
        assertEq(underlyingToken.allowance(address(lpManager), address(router)), 0);
    }

    function testAddLiquidityRejectsUnauthorizedCallerAndZeroAmounts() public {
        vm.expectRevert("onAuthorizedCaller");
        lpManager.addLiquidity(1, 1, recipient);

        vm.prank(manager);
        lpManager.addAuthorizedCaller(authorizedCaller);
        vm.startPrank(authorizedCaller);
        vm.expectRevert("Amounts must be greater than 0");
        lpManager.addLiquidity(0, 1, recipient);
        vm.expectRevert("Amounts must be greater than 0");
        lpManager.addLiquidity(1, 0, recipient);
        vm.stopPrank();
    }

    function testReceiveNativeToken() public {
        vm.deal(recipient, 1 ether);
        vm.prank(recipient);
        (bool success,) = address(lpManager).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(lpManager).balance, 1 ether);
    }
}
