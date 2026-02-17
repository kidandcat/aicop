-- Longest Increasing Subsequence (strictly increasing) using patience sorting
-- with binary search.
--
-- Maintains a "tails" array where Tails(I) is the smallest tail element of all
-- increasing subsequences of length I. For each element, binary search
-- (Lower_Bound) finds the leftmost position where Tails(Pos) >= element:
--   - If beyond the current length, append (extends LIS).
--   - Otherwise, replace at the found position (keeps tails minimal).
--
-- Time: O(N log N), Space: O(N)

with Ada.Text_IO;  use Ada.Text_IO;

procedure Solution is

   package LLI_IO is new Ada.Text_IO.Integer_IO (Long_Long_Integer);
   use LLI_IO;

   package Int_IO is new Ada.Text_IO.Integer_IO (Integer);
   use Int_IO;

   type Long_Array is array (Positive range <>) of Long_Long_Integer;

   --  Binary search for the leftmost position in Tails (1 .. Len)
   --  where Tails (Pos) >= Val (lower_bound equivalent).
   --  Returns a value in 1 .. Len + 1.
   function Lower_Bound
     (Tails : Long_Array;
      Len   : Natural;
      Val   : Long_Long_Integer) return Positive
   is
      Lo  : Positive := 1;
      Hi  : Natural  := Len + 1;
      Mid : Positive;
   begin
      while Lo < Hi loop
         Mid := Lo + (Hi - Lo) / 2;
         if Tails (Mid) < Val then
            Lo := Mid + 1;
         else
            Hi := Mid;
         end if;
      end loop;
      return Lo;
   end Lower_Bound;

   N : Integer;

begin
   Int_IO.Get (N);

   if N <= 0 then
      Put_Line ("0");
      return;
   end if;

   declare
      Arr     : Long_Array (1 .. N);
      Tails   : Long_Array (1 .. N);
      Lis_Len : Natural := 0;
      Pos     : Positive;
      Val     : Long_Long_Integer;
   begin
      --  Read input values.
      for I in 1 .. N loop
         LLI_IO.Get (Arr (I));
      end loop;

      --  Build the tails array using patience sorting.
      for I in 1 .. N loop
         Val := Arr (I);
         Pos := Lower_Bound (Tails, Lis_Len, Val);
         Tails (Pos) := Val;
         if Pos = Lis_Len + 1 then
            Lis_Len := Lis_Len + 1;
         end if;
      end loop;

      Int_IO.Put (Lis_Len, Width => 0);
      New_Line;
   end;
end Solution;
