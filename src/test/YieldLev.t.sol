// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "ds-test/test.sol";

import {YieldLadle, YieldLever} from "../YieldLev.sol";

interface VM {
    function prank(address sender) external;
    function warp(uint timestamp) external;
    function roll(uint blockNumber) external;
}

interface YieldPool {
    function getCache() external returns (uint112, uint112, uint32);
}

interface YieldCauldron {
    function balances(bytes12) external returns (uint128, uint128);
}


interface IUSDC {
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    // admin
    function masterMinter() external returns(address);
    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);
    function mint(address _to, uint256 _amount) external returns (bool);
}


contract ContractTest is DSTest {
    IUSDC constant _usdc = IUSDC(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    VM constant _vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    YieldLadle _ladle;
    YieldLever _lever;
    YieldPool _pool;

    uint constant baseAmount = 250 * 1e3 * 1e6; // 250k USDC
    uint constant borrowAmount = 750 * 1e3 * 1e6; // 750k USDC
    uint constant maxFyAmount = borrowAmount + 7 * 1e3 * 1e6; // borrowAmount + 7k
    bytes6 seriesId = 0x303230350000; // FYUSDC05LP

    bytes12 vaultId; // computed in setUp()
    int128 inkAmount;


    function setUp() public {
        _vm.prank(_usdc.masterMinter());
        _usdc.configureMinter(address(this), baseAmount); // 250k USDC
        _usdc.mint(address(this), baseAmount);

        _ladle = YieldLadle(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);
        _lever = new YieldLever(_ladle);
        
        _usdc.approve(address(_lever), baseAmount);

        uint8 salt = 0;
        vaultId = bytes12(keccak256(abi.encodePacked(address(_lever), block.timestamp, salt)));
        _pool = YieldPool(_ladle.pools(seriesId));

        (, uint112 fyTokens,) = _pool.getCache();
        _lever.invest(baseAmount, borrowAmount, maxFyAmount, seriesId);
        (, uint112 fyTokens2,) = _pool.getCache();
        inkAmount = int128(uint128(fyTokens)) - int128(uint128(fyTokens2));

        emit log_named_uint("base", _usdc.balanceOf(address(_lever)));
    }

    function computeStats() internal {
        (uint128 debt, uint128 collateral) = YieldCauldron(_ladle.cauldron()).balances(vaultId);
        assertEq(debt, 0);
        uint256 balance = _usdc.balanceOf(address(this)) + collateral;
        emit log_named_uint("collateral in vault", collateral / 1e6);
        emit log_named_uint("collateral in wallet", (balance - collateral) / 1e6);
        emit log_named_int("profit", (int256(balance) - int256(baseAmount)) / 1e6);
    }

    function testImmediateWithdraw() public {
        _lever.unwind(vaultId, maxFyAmount, _ladle.pools(seriesId), inkAmount);
        computeStats();
    }

    function testWithdrawIn1Week() public {
        _vm.roll(block.number + 1);
        _vm.warp(block.timestamp + 3600 * 24 * 7);
        _lever.unwind(vaultId, maxFyAmount, _ladle.pools(seriesId), inkAmount);
        computeStats();
    }

    function testWithdrawIn2Months() public {
        _vm.roll(block.number + 1);
        _vm.warp(block.timestamp + 3600 * 24 * 30 * 2);
        _lever.unwind(vaultId, maxFyAmount, _ladle.pools(seriesId), inkAmount);
        computeStats();
    }

    function testWithdrawIn1Year() public {
        _vm.roll(block.number + 1);
        _vm.warp(block.timestamp + 3600 * 24 * 365);
        _lever.unwind(vaultId, maxFyAmount, _ladle.pools(seriesId), inkAmount);
        computeStats();
    }

}
