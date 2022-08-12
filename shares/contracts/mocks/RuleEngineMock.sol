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
import "../interface/IRuleEngine.sol";
import "./RuleMock.sol";

/** ADD AUTHORIZATION MODULE FOR SECURITY
 * ADD OPERATOR HERE WHICH IS SET BY THE STOCK CONTRACT WHEN A RULEENGINE IS SET
 */

contract RuleEngineMock is IRuleEngine {
    IRule[] internal _rules;
    mapping(IRule => bool) internal _rulesRegistered;

    //dropped constructor**********

    function setRules(IRule[] calldata rules) external {
        _rules = rules;
        for (uint256 i = 0; i < rules.length; i++) {
            _rulesRegistered[rules[i]] = true;
        }
    }

    function addRules(IRule[] calldata rules) external {
        for (uint256 i = 0; i < rules.length; i++) {
            if (!_rulesRegistered[rules[i]]) {
                _rulesRegistered[rules[i]] = true;
                _rules.push(rules[i]);
            }
        }
    }

    function removeRule(uint256 index) public {
        IRule temp = _rules[index];
        _rules[index] = _rules[_rules.length - 1];
        _rules[_rules.length - 1] = temp;
        _rules.pop();
        _rulesRegistered[temp] = false;
    }

    function ruleLength() external view returns (uint256) {
        return _rules.length;
    }

    function getRule(uint256 ruleId) external view returns (IRule) {
        return _rules[ruleId];
    }

    function getRules() external view returns (IRule[] memory) {
        return _rules;
    }

    /**
     * @dev is called by the Stock contract. Function checks for rules in each Rule Contract and should return 0x51 on success due to the ERC1066 convention or return the corresponding restriction code
     * @notice ERC1066 is found in RestrictionCodes and the dictionary of restrictions is within the shares contract
     **/
    function detectTransferRestriction(
        address _from,
        address _to,
        uint256 _amount
    ) public view returns (uint8) {
        for (uint256 i = 0; i < _rules.length; i++) {
            uint8 restriction = _rules[i].detectTransferRestriction(
                _from,
                _to,
                _amount
            );
            if (restriction != 0x51) {
                return restriction;
            }
        }
        return 0x51;
    }

    function validateTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) public view returns (bool) {
        return detectTransferRestriction(_from, _to, _amount) == 0x51;
    }

    /** @notice RULES must stick to the convention to ensure transparency when looking up a restriction code */
    function messageForTransferRestriction(uint8 _restrictionCode)
        public
        view
        returns (string memory)
    {
        for (uint256 i = 0; i < _rules.length; i++) {
            if (_rules[i].canReturnTransferRestrictionCode(_restrictionCode)) {
                return
                    _rules[i].messageForTransferRestriction(_restrictionCode);
            }
        }
        return "unknown code";
    }
}
