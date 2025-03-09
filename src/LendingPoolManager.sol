// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import {LendingPool} from "./LendingPool.sol";

contract LendingPoolManager is Ownable, ReentrancyGuard {
    using Strings for uint256;

    error LendingPoolNotFound();

    event LendingPoolCreated(bytes32 key, address indexed creator, LendingPool.LendingPoolInfo info);

    mapping(bytes32 => LendingPool) public lendingPools;

    constructor() Ownable(msg.sender) {}

    function _generateLendingPoolKey(
        address debtToken_,
        address collateralToken_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(debtToken_, collateralToken_, maturityMonth_, maturityYear_));
    }

    function createLendingPool(
        address debtToken_,
        address collateralToken_,
        address oracle_,
        uint256 maturity_,
        string memory maturityMonth_,
        uint256 maturityYear_,
        uint256 ltv_
    ) external nonReentrant {
        bytes32 key = _generateLendingPoolKey(debtToken_, collateralToken_, maturityMonth_, maturityYear_);
        LendingPool.LendingPoolInfo memory info = LendingPool.LendingPoolInfo({
            debtToken: debtToken_,
            collateralToken: collateralToken_,
            oracle: oracle_,
            maturity: maturity_,
            maturityMonth: maturityMonth_,
            maturityYear: maturityYear_,
            ltv: ltv_
        });
        lendingPools[key] = new LendingPool(msg.sender, info);

        emit LendingPoolCreated(key, msg.sender, info);
    }

    function getLendingPool(
        address debtToken_,
        address collateralToken_,
        string memory maturityMonth_,
        uint256 maturityYear_
    ) external view returns (address) {
        bytes32 key = _generateLendingPoolKey(debtToken_, collateralToken_, maturityMonth_, maturityYear_);
        if (address(lendingPools[key]) == address(0)) revert LendingPoolNotFound();
        return address(lendingPools[key]);
    }
}