/**
 *Submitted for verification at Etherscan.io on 2018-08-03
 * 提交到 Etherscan.io 进行验证，日期：2018-08-03
 */

pragma solidity ^0.4.24; // 使用 Solidity 0.4.24 版本或更高

// File: zos-lib/contracts/upgradeability/Proxy.sol

/**
 * @title Proxy
 * @dev Implements delegation of calls to other contracts, with proper
 * forwarding of return values and bubbling of failures.
 * It defines a fallback function that delegates all calls to the address
 * returned by the abstract _implementation() internal function.
 *
 * 代理合约
 * 实现将调用委托给其他合约，并正确转发返回值和传播失败。
 * 定义了一个回退函数，将所有调用委托给抽象函数 _implementation() 返回的地址。
 */
contract Proxy {
    /**
     * @dev Fallback function.
     * Implemented entirely in `_fallback`.
     *
     * 回退函数（可接收以太币）
     * 完全在 `_fallback` 中实现。
     * 当调用合约中不存在的函数时，会触发此函数。
     */
    function() external payable {
        _fallback();
    }

    /**
     * @return The Address of the implementation.
     *
     * 返回实现合约的地址
     * 这是一个抽象函数，需要在子合约中实现
     */
    function _implementation() internal view returns (address);

    /**
     * @dev Delegates execution to an implementation contract.
     * This is a low level function that doesn't return to its internal call site.
     * It will return to the external caller whatever the implementation returns.
     * @param implementation Address to delegate.
     *
     * 将执行委托给实现合约
     * 这是一个底层函数，不会返回到其内部调用点。
     * 它会将实现合约返回的任何内容返回给外部调用者。
     * @param implementation 要委托的合约地址
     */
    function _delegate(address implementation) internal {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            // 复制 msg.data。我们在这个内联汇编块中完全控制内存，
            // 因为它不会返回到 Solidity 代码。我们覆盖位置 0 处的 Solidity 暂存区。
            calldatacopy(0, 0, calldatasize)

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            // 调用实现合约
            // out 和 outsize 为 0，因为我们还不知道返回数据的大小
            // delegatecall: 在目标合约的上下文中执行代码，但使用当前合约的存储
            let result := delegatecall(
                gas,
                implementation,
                0,
                calldatasize,
                0,
                0
            )

            // Copy the returned data.
            // 复制返回的数据
            returndatacopy(0, 0, returndatasize)

            switch result
            // delegatecall returns 0 on error.
            // delegatecall 在错误时返回 0
            case 0 {
                revert(0, returndatasize)
            } // 如果调用失败，回滚交易
            default {
                return(0, returndatasize)
            } // 如果调用成功，返回数据
        }
    }

    /**
     * @dev Function that is run as the first thing in the fallback function.
     * Can be redefined in derived contracts to add functionality.
     * Redefinitions must call super._willFallback().
     *
     * 在回退函数中首先运行的函数
     * 可以在派生合约中重新定义以添加功能
     * 重新定义时必须调用 super._willFallback()
     */
    function _willFallback() internal {}

    /**
     * @dev fallback implementation.
     * Extracted to enable manual triggering.
     *
     * 回退函数的实现
     * 提取出来以便可以手动触发
     */
    function _fallback() internal {
        _willFallback(); // 执行回退前的钩子函数
        _delegate(_implementation()); // 委托调用实现合约
    }
}

// File: openzeppelin-solidity/contracts/AddressUtils.sol

/**
 * Utility library of inline functions on addresses
 * 地址工具库，提供地址相关的内联函数
 */
library AddressUtils {
    /**
     * Returns whether the target address is a contract
     * @dev This function will return false if invoked during the constructor of a contract,
     * as the code is not actually created until after the constructor finishes.
     * @param addr address to check
     * @return whether the target address is a contract
     *
     * 返回目标地址是否为合约
     * 注意：如果在合约构造函数期间调用此函数，将返回 false，
     * 因为在构造函数完成之前，代码实际上还没有创建。
     * @param addr 要检查的地址
     * @return 目标地址是否为合约
     */
    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        // XXX Currently there is no better way to check if there is a contract in an address
        // than to check the size of the code at that address.
        // See https://ethereum.stackexchange.com/a/14016/36603
        // for more details about how this works.
        // TODO Check this again before the Serenity release, because all addresses will be
        // contracts then.
        // 目前没有比检查该地址处代码大小更好的方法来检查地址是否为合约
        // 在 Serenity 发布之前需要再次检查，因为那时所有地址都将是合约
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            size := extcodesize(addr)
        } // 获取地址处的代码大小
        return size > 0; // 如果代码大小大于 0，说明是合约地址
    }
}

// File: zos-lib/contracts/upgradeability/UpgradeabilityProxy.sol

/**
 * @title UpgradeabilityProxy
 * @dev This contract implements a proxy that allows to change the
 * implementation address to which it will delegate.
 * Such a change is called an implementation upgrade.
 *
 * 可升级代理合约
 * 此合约实现了一个代理，允许更改它将委托给的实现地址。
 * 这种更改称为实现升级。
 */
contract UpgradeabilityProxy is Proxy {
    /**
     * @dev Emitted when the implementation is upgraded.
     * @param implementation Address of the new implementation.
     *
     * 当实现升级时发出的事件
     * @param implementation 新实现的地址
     */
    event Upgraded(address implementation);

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "org.zeppelinos.proxy.implementation", and is
     * validated in the constructor.
     *
     * 存储当前实现地址的存储槽
     * 这是 "org.zeppelinos.proxy.implementation" 的 keccak-256 哈希值，
     * 在构造函数中进行验证。
     * 使用存储槽可以避免与实现合约的存储变量冲突
     */
    bytes32 private constant IMPLEMENTATION_SLOT =
        0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3;

    /**
     * @dev Contract constructor.
     * @param _implementation Address of the initial implementation.
     *
     * 合约构造函数
     * @param _implementation 初始实现的地址
     */
    constructor(address _implementation) public {
        // 验证存储槽的哈希值是否正确（防止存储槽被错误修改）
        assert(
            IMPLEMENTATION_SLOT ==
                keccak256("org.zeppelinos.proxy.implementation")
        );

        _setImplementation(_implementation); // 设置初始实现地址
    }

    /**
     * @dev Returns the current implementation.
     * @return Address of the current implementation
     *
     * 返回当前实现合约的地址
     * @return 当前实现的地址
     */
    function _implementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            // 从存储槽中读取实现地址
            impl := sload(slot)
        }
    }

    /**
     * @dev Upgrades the proxy to a new implementation.
     * @param newImplementation Address of the new implementation.
     *
     * 将代理升级到新的实现
     * @param newImplementation 新实现的地址
     */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation); // 设置新的实现地址
        emit Upgraded(newImplementation); // 发出升级事件
    }

    /**
     * @dev Sets the implementation address of the proxy.
     * @param newImplementation Address of the new implementation.
     *
     * 设置代理的实现地址
     * @param newImplementation 新实现的地址
     */
    function _setImplementation(address newImplementation) private {
        // 确保新实现地址是一个合约地址（不能是普通账户地址）
        require(
            AddressUtils.isContract(newImplementation),
            "Cannot set a proxy implementation to a non-contract address"
        );

        bytes32 slot = IMPLEMENTATION_SLOT;

        assembly {
            // 将新实现地址存储到指定的存储槽中
            sstore(slot, newImplementation)
        }
    }
}

// File: zos-lib/contracts/upgradeability/AdminUpgradeabilityProxy.sol

/**
 * @title AdminUpgradeabilityProxy
 * @dev This contract combines an upgradeability proxy with an authorization
 * mechanism for administrative tasks.
 * All external functions in this contract must be guarded by the
 * `ifAdmin` modifier. See ethereum/solidity#3864 for a Solidity
 * feature proposal that would enable this to be done automatically.
 *
 * 管理员可升级代理合约
 * 此合约将可升级代理与用于管理任务的授权机制相结合。
 * 此合约中的所有外部函数都必须由 `ifAdmin` 修饰符保护。
 */
contract AdminUpgradeabilityProxy is UpgradeabilityProxy {
    /**
     * @dev Emitted when the administration has been transferred.
     * @param previousAdmin Address of the previous admin.
     * @param newAdmin Address of the new admin.
     *
     * 当管理权转移时发出的事件
     * @param previousAdmin 前一个管理员的地址
     * @param newAdmin 新管理员的地址
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "org.zeppelinos.proxy.admin", and is
     * validated in the constructor.
     *
     * 存储合约管理员的存储槽
     * 这是 "org.zeppelinos.proxy.admin" 的 keccak-256 哈希值，
     * 在构造函数中进行验证。
     */
    bytes32 private constant ADMIN_SLOT =
        0x10d6a54a4754c8869d6886b5f5d7fbfa5b4522237ea5c60d11bc4e7a1ff9390b;

    /**
     * @dev Modifier to check whether the `msg.sender` is the admin.
     * If it is, it will run the function. Otherwise, it will delegate the call
     * to the implementation.
     *
     * 修饰符：检查 `msg.sender` 是否为管理员
     * 如果是管理员，则执行函数；否则，将调用委托给实现合约。
     * 这是代理模式的关键：管理员调用执行管理功能，普通用户调用转发到实现合约
     */
    modifier ifAdmin() {
        if (msg.sender == _admin()) {
            _; // 如果是管理员，执行函数体
        } else {
            _fallback(); // 如果不是管理员，转发到实现合约
        }
    }

    /**
     * Contract constructor.
     * It sets the `msg.sender` as the proxy administrator.
     * @param _implementation address of the initial implementation.
     *
     * 合约构造函数
     * 将 `msg.sender` 设置为代理管理员
     * @param _implementation 初始实现的地址
     */
    constructor(
        address _implementation
    ) public UpgradeabilityProxy(_implementation) {
        // 验证管理员存储槽的哈希值
        assert(ADMIN_SLOT == keccak256("org.zeppelinos.proxy.admin"));

        _setAdmin(msg.sender); // 将部署者设置为管理员
    }

    /**
     * @return The address of the proxy admin.
     *
     * 返回代理管理员的地址
     * 只有管理员可以调用此函数
     */
    function admin() external view ifAdmin returns (address) {
        return _admin();
    }

    /**
     * @return The address of the implementation.
     *
     * 返回实现合约的地址
     * 只有管理员可以调用此函数
     */
    function implementation() external view ifAdmin returns (address) {
        return _implementation();
    }

    /**
     * @dev Changes the admin of the proxy.
     * Only the current admin can call this function.
     * @param newAdmin Address to transfer proxy administration to.
     *
     * 更改代理的管理员
     * 只有当前管理员可以调用此函数
     * @param newAdmin 要转移代理管理权的地址
     */
    function changeAdmin(address newAdmin) external ifAdmin {
        require(
            newAdmin != address(0),
            "Cannot change the admin of a proxy to the zero address"
        );
        emit AdminChanged(_admin(), newAdmin); // 发出管理员变更事件
        _setAdmin(newAdmin); // 设置新管理员
    }

    /**
     * @dev Upgrade the backing implementation of the proxy.
     * Only the admin can call this function.
     * @param newImplementation Address of the new implementation.
     *
     * 升级代理的后备实现
     * 只有管理员可以调用此函数
     * @param newImplementation 新实现的地址
     */
    function upgradeTo(address newImplementation) external ifAdmin {
        _upgradeTo(newImplementation);
    }

    /**
     * @dev Upgrade the backing implementation of the proxy and call a function
     * on the new implementation.
     * This is useful to initialize the proxied contract.
     * @param newImplementation Address of the new implementation.
     * @param data Data to send as msg.data in the low level call.
     * It should include the signature and the parameters of the function to be
     * called, as described in
     * https://solidity.readthedocs.io/en/develop/abi-spec.html#function-selector-and-argument-encoding.
     *
     * 升级代理的后备实现并在新实现上调用函数
     * 这对于初始化被代理的合约很有用
     * @param newImplementation 新实现的地址
     * @param data 在底层调用中作为 msg.data 发送的数据
     * 应包含要调用的函数的签名和参数（ABI 编码格式）
     */
    function upgradeToAndCall(
        address newImplementation,
        bytes data
    ) external payable ifAdmin {
        _upgradeTo(newImplementation); // 先升级实现
        require(address(this).call.value(msg.value)(data)); // 然后调用新实现的函数（可发送以太币）
    }

    /**
     * @return The admin slot.
     *
     * 返回管理员地址
     * 从存储槽中读取管理员地址
     */
    function _admin() internal view returns (address adm) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            adm := sload(slot) // 从存储槽读取管理员地址
        }
    }

    /**
     * @dev Sets the address of the proxy admin.
     * @param newAdmin Address of the new proxy admin.
     *
     * 设置代理管理员的地址
     * @param newAdmin 新代理管理员的地址
     */
    function _setAdmin(address newAdmin) internal {
        bytes32 slot = ADMIN_SLOT;

        assembly {
            sstore(slot, newAdmin) // 将新管理员地址存储到存储槽
        }
    }

    /**
     * @dev Only fall back when the sender is not the admin.
     *
     * 只有当发送者不是管理员时才回退
     * 防止管理员通过回退函数直接调用实现合约
     */
    function _willFallback() internal {
        require(
            msg.sender != _admin(),
            "Cannot call fallback function from the proxy admin"
        );
        super._willFallback(); // 调用父类的 _willFallback
    }
}

// File: contracts/FiatTokenProxy.sol

/**
 * Copyright CENTRE SECZ 2018
 * 版权归 CENTRE SECZ 2018 所有
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is furnished to
 * do so, subject to the following conditions:
 *
 * 特此免费授予任何获得本软件及其相关文档文件（"软件"）副本的人不受限制地
 * 处理软件的权利，包括但不限于使用、复制、修改、合并、发布、分发、再许可
 * 和/或出售软件副本的权利，并允许向其提供软件的人员这样做，但须符合以下条件：
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * 上述版权声明和本许可声明应包含在软件的所有副本或重要部分中。
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * 软件按"原样"提供，不提供任何形式的明示或暗示保证，包括但不限于对适销性、
 * 特定用途的适用性和非侵权性的保证。在任何情况下，作者或版权持有人均不对
 * 任何索赔、损害或其他责任负责，无论是在合同诉讼、侵权行为或其他方面，
 * 由软件或软件的使用或其他交易引起、由此产生或与之相关。
 */

pragma solidity ^0.4.24;

/**
 * @title FiatTokenProxy
 * @dev This contract proxies FiatToken calls and enables FiatToken upgrades
 *
 * FiatToken 代理合约（USDC 的代理合约）
 * 此合约代理 FiatToken 的调用并支持 FiatToken 的升级
 *
 * 工作原理：
 * 1. 用户调用 FiatTokenProxy 合约的函数
 * 2. 如果调用的是管理函数（如 upgradeTo），且调用者是管理员，则执行管理功能
 * 3. 否则，调用会被转发到实现合约（FiatToken 实现合约）
 * 4. 实现合约的代码可以升级，但代理合约地址保持不变
 * 5. 这样可以在不改变 USDC 代币合约地址的情况下升级合约逻辑
 *
 * 优势：
 * - 保持合约地址不变（用户无需更新代币地址）
 * - 可以修复 bug 或添加新功能
 * - 保持存储状态不变（余额等数据不会丢失）
 */
contract FiatTokenProxy is AdminUpgradeabilityProxy {
    /**
     * @dev 构造函数
     * @param _implementation FiatToken 实现合约的地址
     *
     * 部署时传入 FiatToken 的实现合约地址
     * 部署者将成为代理合约的管理员，可以升级实现合约
     */
    constructor(
        address _implementation
    ) public AdminUpgradeabilityProxy(_implementation) {}
}
