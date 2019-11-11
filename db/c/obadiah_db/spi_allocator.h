// Copyright (C) 2019 Petr Fedorov <petr.fedorov@phystech.edu>

// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation,  version 2 of the License

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

#ifndef SPI_ALLOCATOR_H
#define SPI_ALLOCATOR_H

#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus

#include "executor/spi.h"
#include "postgres.h"

#ifdef __cplusplus
}
#endif  // __cplusplus
#include <deque>
#include <map>
#include <memory>
#include <set>
#include <unordered_set>
#include <vector>

namespace obad {

template <class T>
class p_allocator {
public:
 using value_type = T;
 using reference = T&;
 using const_reference = const T&;
 using pointer = value_type*;
 using const_pointer =
     typename std::pointer_traits<pointer>::template rebind<value_type const>;

 using difference_type = std::ptrdiff_t;
 using size_type = std::size_t;

 template <class U>
 struct rebind {
  typedef p_allocator<U> other;
 };

 p_allocator() noexcept {}

 template <class U>
 p_allocator(p_allocator<U> const&) noexcept {}

 value_type* allocate(std::size_t n) {
  return static_cast<value_type*>(palloc(n * sizeof(value_type)));
 }

 void deallocate(value_type* p, std::size_t n) noexcept { pfree(p); }

 template <class U>
 void destroy(U* p) noexcept {
  p->~U();
 }
};

template <class T, class U>
bool
operator==(p_allocator<T> const&, p_allocator<U> const&) noexcept {
 return true;
}

template <class T, class U>
bool
operator!=(p_allocator<T> const& x, p_allocator<U> const& y) noexcept {
 return !(x == y);
}

template <class T>
class spi_allocator {
public:
 using value_type = T;
 using reference = T&;
 using const_reference = const T&;
 using pointer = value_type*;
 using const_pointer =
     typename std::pointer_traits<pointer>::template rebind<value_type const>;
 //     using void_pointer       = typename
 // std::pointer_traits<pointer>::template
 //                                                           rebind<void>;
 //     using const_void_pointer = typename
 // std::pointer_traits<pointer>::template
 //                                                           rebind<const
 // void>;

 using difference_type = std::ptrdiff_t;
 using size_type = std::size_t;

 template <class U>
 struct rebind {
  typedef spi_allocator<U> other;
 };

 spi_allocator() noexcept {  // elog(DEBUG1, "spi_allocator instantiated");
 }                           // not required, unless used
 template <class U>
 spi_allocator(spi_allocator<U> const&) noexcept {}

 value_type*  // Use pointer if pointer is not a value_type*
 allocate(std::size_t n) {
  return static_cast<value_type*>(SPI_palloc(n * sizeof(value_type)));
 }

 void deallocate(value_type* p, std::size_t n) noexcept  // Use pointer if
                                                         // pointer is not a
                                                         // value_type*
 {
  SPI_pfree(p);
 }

 //     value_type*
 //     allocate(std::size_t n, const_void_pointer)
 //     {
 //         return allocate(n);
 //     }

 //     template <class U, class ...Args>
 //     void
 //     construct(U* p, Args&& ...args)
 //     {
 //         ::new(p) U(std::forward<Args>(args)...);
 //     }

 template <class U>
 void destroy(U* p) noexcept {
  p->~U();
 }

 //     std::size_t
 //     max_size() const noexcept
 //     {
 //         return std::numeric_limits<size_type>::max();
 //     }

 //     allocator
 //     select_on_container_copy_construction() const
 //     {
 //         return *this;
 //     }

 //     using propagate_on_container_copy_assignment = std::false_type;
 //     using propagate_on_container_move_assignment = std::false_type;
 //     using propagate_on_container_swap            = std::false_type;
 //     using is_always_equal                        =
 // std::is_empty<allocator>;
};

template <class T, class U>
bool
operator==(spi_allocator<T> const&, spi_allocator<U> const&) noexcept {
 return true;
}

template <class T, class U>
bool
operator!=(spi_allocator<T> const& x, spi_allocator<U> const& y) noexcept {
 return !(x == y);
}

enum class allocation_mode { non_spi, spi };

class postgres_heap {
public:
 void* operator new(size_t s) = delete;
 void* operator new[](size_t s) = delete;
 void* operator new(size_t s, allocation_mode);
 void operator delete(void* p, size_t s);
 void operator delete[](void* p, size_t s) = delete;
};

template <class T>
using spi_vector = std::vector<T, spi_allocator<T>>;
template <class T>
using vector = std::vector<T, p_allocator<T>>;
template <class T>
using deque = std::deque<T, p_allocator<T>>;
template <class Key, class T, class Compare = std::less<Key>>
using map = std::map<Key, T, Compare, p_allocator<std::pair<const Key, T>>>;
template <class Key, class Compare = std::less<Key>>
using set = std::set<Key, Compare, p_allocator<Key>>;
template <class Key, class Hash = std::hash<Key>,
          class KeyEqual = std::equal_to<Key>>
using unordered_set = std::unordered_set<Key, Hash, KeyEqual, p_allocator<Key>>;

}  // namespace obad

#endif
