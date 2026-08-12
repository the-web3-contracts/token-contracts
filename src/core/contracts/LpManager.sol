// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@pancake-v2-periphery/interfaces/IPancakeRouter02.sol";

import { LpManagerStorage } from "./LpManagerStorage.sol";

contract LpManager is Initializable, OwnableUpgradeable, PausableUpgradeable, LpManagerStorage {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor() {
        _disableInitializers();
    }

    modifier onlyManager() {
        require(msg.sender == manager, "onlyManager");
        _;
    }

    modifier onAuthorizedCaller() {
        require(authorizedCallers.contains(msg.sender), "onAuthorizedCaller");
        _;
    }

    receive() external payable {}

    function initialize(
        address initialOwner,
        address initialManager,
        address _underlyingToken,
        address _usdt,
        address _v2Router
    ) public initializer {
        require(_v2Router != address(0), "LpManager: _v2Router cannot be zero address");
        __Ownable_init(initialOwner);
        manager = initialManager;
        underlyingToken = _underlyingToken;
        USDT = _usdt;
        v2Router = _v2Router;
    }

    function addAuthorizedCaller(address caller) external onlyManager {
        authorizedCallers.add(caller);
    }

    function removeAuthorizedCaller(address caller) external onlyManager {
        authorizedCallers.remove(caller);
    }

    function getAuthorizedCallers() external view returns (address[] memory) {
        return EnumerableSet.values(authorizedCallers);
    }

    function setManager(address _manager) external onlyOwner {
        require(_manager != address(0), "manager cannot be zero address");
        manager = _manager;
    }

    function withdraw(address recipient, uint256 amount) external onlyManager {
        require(amount <= _tokenBalance(), "withdraw amount more token balance in this contracts");

        IERC20(underlyingToken).safeTransfer(recipient, amount);

        emit Withdraw(underlyingToken, recipient, amount);
    }

    function addLiquidity(uint256 tokenAmount, uint256 usdtAmount, address to) external onAuthorizedCaller {
        require(tokenAmount > 0 && usdtAmount > 0, "Amounts must be greater than 0");

        IERC20(underlyingToken).approve(v2Router, tokenAmount);

        IERC20(USDT).approve(v2Router, usdtAmount);

        (uint256 amount0Used, uint256 amount1Used, uint256 liquidityAdded) = IPancakeRouter02(v2Router)
            .addLiquidity(USDT, underlyingToken, usdtAmount, tokenAmount, 0, 0, to, block.timestamp);

        emit LiquidityAdded(liquidityAdded, amount0Used, amount1Used);
    }

    // ========= internal =========
    function _tokenBalance() internal view virtual returns (uint256) {
        return IERC20(underlyingToken).balanceOf(address(this));
    }
}
