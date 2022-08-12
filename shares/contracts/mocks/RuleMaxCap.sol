// SPDX-License-Identifier: ALEX

/*
 * Copyright (c) Capital Market and Technology Association, 2018-2019
 * https://cmta.ch
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

pragma solidity ^0.8.0;

import "../interface/IRule.sol";
import "C:/Users/Alex Nikolic/Desktop/CFCoding/UseCases/shares/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "C:/Users/Alex Nikolic/Desktop/CFCoding/UseCases/shares/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @dev represents a mock rule and shows how rules should be set up and integrated into the RuleEngine, which by itself is integrated into the Stock contract.
 * @notice this is a max cap for shareholders, no one can have more than 5000 shares
 * @notice some RULES are dependent on context like this one, others can be universally applicable like transfer volume exceeded
 **/
contract MaxCap is IRule, Ownable {
    uint8 constant BALANCE_TOO_HIGH = 0x57;
    string constant TEXT_BALANCE_TOO_HIGH = "exeeds max cap";
    string constant TEXT_CODE_NOT_FOUND = "Code not found";

    IERC20 public ruled;
    uint256 private _maxCap;

    constructor(address _ruled, uint256 maxcap) {
        ruled = IERC20(_ruled);
        _maxCap = maxcap;
    }

    function isTransferValid(
        address _from,
        address _to,
        uint256 _amount
    ) public view returns (bool isValid) {
        return detectTransferRestriction(_from, _to, _amount) == 0x51;
    }

    function setMaxCap(uint256 num) public onlyOwner {
        _maxCap = num;
    }

    function getMaxCap() public view returns (uint256) {
        return _maxCap;
    }

    function detectTransferRestriction(
        address, /* _from */
        address _to,
        uint256 _amount
    ) public view returns (uint8) {
        if (ruled.balanceOf(_to) + _amount > getMaxCap()) {
            return BALANCE_TOO_HIGH;
        }
        return 0x51;
    }

    function canReturnTransferRestrictionCode(uint8 _restrictionCode)
        public
        pure
        returns (bool)
    {
        return _restrictionCode == BALANCE_TOO_HIGH;
    }

    function messageForTransferRestriction(uint8 _restrictionCode)
        external
        pure
        returns (string memory)
    {
        return
            _restrictionCode == BALANCE_TOO_HIGH
                ? TEXT_BALANCE_TOO_HIGH
                : TEXT_CODE_NOT_FOUND;
    }
}
