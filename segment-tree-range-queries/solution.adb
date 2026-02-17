--  Segment tree with point updates and range sum queries.
--  Array-based implementation using 1-indexed tree of size 4*N.
--
--  Operations:
--    1 i v  -> set arr(i) = v (1-indexed)
--    2 l r  -> query sum of arr(l..r) (1-indexed, inclusive)
--
--  Time: O(log N) per operation, Space: O(N)

with Ada.Text_IO;
with Ada.Integer_Text_IO;
with Ada.Long_Long_Integer_Text_IO;

procedure Solution is

   Max_N : constant := 200_000;
   Max_Tree : constant := 4 * Max_N + 4;

   Tree : array (1 .. Max_Tree) of Long_Long_Integer := (others => 0);
   Data : array (1 .. Max_N) of Long_Long_Integer;
   N, Q : Integer;

   procedure Build (Node, Start, Finish : Integer) is
      Mid : Integer;
   begin
      if Start = Finish then
         Tree (Node) := Data (Start);
      else
         Mid := (Start + Finish) / 2;
         Build (2 * Node, Start, Mid);
         Build (2 * Node + 1, Mid + 1, Finish);
         Tree (Node) := Tree (2 * Node) + Tree (2 * Node + 1);
      end if;
   end Build;

   procedure Update (Node, Start, Finish, Idx : Integer;
                     Val : Long_Long_Integer) is
      Mid : Integer;
   begin
      if Start = Finish then
         Tree (Node) := Val;
      else
         Mid := (Start + Finish) / 2;
         if Idx <= Mid then
            Update (2 * Node, Start, Mid, Idx, Val);
         else
            Update (2 * Node + 1, Mid + 1, Finish, Idx, Val);
         end if;
         Tree (Node) := Tree (2 * Node) + Tree (2 * Node + 1);
      end if;
   end Update;

   function Query (Node, Start, Finish, L, R : Integer)
      return Long_Long_Integer is
      Mid       : Integer;
      Left_Sum  : Long_Long_Integer;
      Right_Sum : Long_Long_Integer;
   begin
      if R < Start or Finish < L then
         return 0;
      end if;
      if L <= Start and Finish <= R then
         return Tree (Node);
      end if;
      Mid := (Start + Finish) / 2;
      Left_Sum := Query (2 * Node, Start, Mid, L, R);
      Right_Sum := Query (2 * Node + 1, Mid + 1, Finish, L, R);
      return Left_Sum + Right_Sum;
   end Query;

   Query_Type : Integer;
   Idx, Val   : Integer;
   L, R       : Integer;
   Result     : Long_Long_Integer;

begin
   Ada.Integer_Text_IO.Get (N);
   Ada.Integer_Text_IO.Get (Q);

   for I in 1 .. N loop
      Ada.Long_Long_Integer_Text_IO.Get (Data (I));
   end loop;

   Build (1, 1, N);

   for I in 1 .. Q loop
      Ada.Integer_Text_IO.Get (Query_Type);
      if Query_Type = 1 then
         Ada.Integer_Text_IO.Get (Idx);
         Ada.Integer_Text_IO.Get (Val);
         Update (1, 1, N, Idx, Long_Long_Integer (Val));
      else
         Ada.Integer_Text_IO.Get (L);
         Ada.Integer_Text_IO.Get (R);
         Result := Query (1, 1, N, L, R);
         Ada.Long_Long_Integer_Text_IO.Put (Result, Width => 0);
         Ada.Text_IO.New_Line;
      end if;
   end loop;
end Solution;
