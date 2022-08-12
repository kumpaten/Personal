// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "C:/Users/Alex Nikolic/Desktop/CFCoding/UseCases/shares/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "C:/Users/Alex Nikolic/Desktop/CFCoding/UseCases/shares/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title Contract that will work with ERC223 tokens.
 */

interface IERC223Recipient {
    /**
     * @dev Standard ERC223 function that will handle incoming token transfers.
     *
     * @param from  Token sender address.
     * @param value Amount of tokens.
     * @param data  Transaction metadata.
     */
    function tokenFallback(
        address from,
        uint256 value,
        bytes memory data
    ) external;
}

contract OCF is ERC20, Ownable {
    error notWhitelisted();

    address[] private _arrayWhitelist;
    mapping(address => bool) private _whitelist;

    constructor(address TR, address[] memory whitelist)
        ERC20("PersonalStableCoin", "OCF")
    {
        transferOwnership(TR); //option to designate owner
        // decimals are fixed at 18, previously used _setDcimals(6)
        _mint(owner(), 10000000000 * 10**decimals()); //10 1e6 previously

        if (whitelist.length > 0) {
            _arrayWhitelist = whitelist;
        }
        _arrayWhitelist.push(owner());

        for (uint256 i = 0; i < _arrayWhitelist.length; i++) {
            _whitelist[_arrayWhitelist[i]] = true;
        }
    }

    modifier whitelisted() {
        // SUBJECT IN QUESTION: NECESSARY?
        if (!isContract(msg.sender)) {
            require(isWhitelisted(msg.sender), "sender not whitelisted");
        }
        _;
    }

    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    function transfer(address _to, uint256 _value)
        public
        override
        whitelisted
        returns (bool)
    {
        bytes memory empty = hex"00000000";
        // add potential whitelist check to prevent delegatecalls from malicious contracts with tokenfallback
        if (isContract(_to)) {
            // && _whitelist[_to] as potential security
            IERC223Recipient receiver = IERC223Recipient(_to);
            receiver.tokenFallback(msg.sender, _value, empty);
        } else {
            if (!isWhitelisted(_to)) {
                revert notWhitelisted(); // slightly dirty. ALL contracts are implicitly whitelisted. Necessary because we can not add the bond contract later. Solved by dynamic whitelists. (deprecated)
            }
        }
        return super.transfer(_to, _value);
    }

    function isWhitelisted(address ad) public view returns (bool) {
        return _whitelist[ad];
    }

    function addToWhitelist(address destination) public onlyOwner {
        _whitelist[destination] = true;
        _arrayWhitelist.push(destination);
    }

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    receive() external payable {}

    fallback() external payable {}
}
