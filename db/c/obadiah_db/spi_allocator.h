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
#endif // __cplusplus

#include "postgres.h"
#include "executor/spi.h"

#ifdef __cplusplus
}
#endif // __cplusplus


namespace obadiah_db {

    template <class T>
    class spi_allocator
    {
    public:
        using value_type    = T;
        using reference = T&;
        using const_reference = const T&;
        using pointer       = value_type*;
        using const_pointer = typename std::pointer_traits<pointer>::template rebind<value_type const>;
    //     using void_pointer       = typename std::pointer_traits<pointer>::template
    //                                                           rebind<void>;
    //     using const_void_pointer = typename std::pointer_traits<pointer>::template
    //                                                           rebind<const void>;

        using difference_type = std::ptrdiff_t;
        using size_type       = std::size_t;

        template <class U> struct rebind {typedef spi_allocator<U> other;};

        spi_allocator() noexcept {   //elog(DEBUG1, "spi_allocator instantiated");
        }  // not required, unless used
        template <class U> spi_allocator(spi_allocator<U> const&) noexcept {}

        value_type*  // Use pointer if pointer is not a value_type*
        allocate(std::size_t n)
        {
            // elog(DEBUG1, "Allocated %lu", n*sizeof(value_type));
            return static_cast<value_type*>(SPI_palloc(n*sizeof(value_type)));
        }

        void
        deallocate(value_type* p, std::size_t n) noexcept  // Use pointer if pointer is not a value_type*
        {
            // elog(DEBUG1, "Deallocated: %lu", n*sizeof(value_type));
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
         void
         destroy(U* p) noexcept
         {
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
    //     using is_always_equal                        = std::is_empty<allocator>;
    };

}

#endif
