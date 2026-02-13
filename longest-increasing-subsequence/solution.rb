# Longest Increasing Subsequence - O(N log N) solution using patience sorting.
#
# Algorithm:
#   Maintain a 'tails' array where tails[i] is the smallest tail element of all
#   increasing subsequences of length i+1. For each element, use binary search
#   to find where it belongs in tails:
#     - If it's larger than all elements in tails, append it (extends LIS).
#     - Otherwise, replace the first element >= it (keeps tails as small as possible).
#   The answer is tails.length.

def lis_length(nums)
  tails = []

  nums.each do |x|
    # bsearch_index finds the index of the first element for which the block
    # returns true. We want the first position where tails[pos] >= x.
    pos = tails.bsearch_index { |val| val >= x }

    if pos.nil?
      # x is larger than all elements in tails; extend the LIS.
      tails << x
    else
      # Replace tails[pos] with x to keep the tail as small as possible.
      tails[pos] = x
    end
  end

  tails.length
end

# Read input
n = gets.to_i
nums = gets.split.map(&:to_i)

puts lis_length(nums)
