--  Dijkstra's shortest path from node 1 to node N using a binary min-heap
--  priority queue and adjacency list representation.
--
--  Time: O((N + M) log N), Space: O(N + M)
--  Compile: gnatmake -O2 -o solution_ada solution.adb

with Ada.Text_IO;
with Ada.Integer_Text_IO;
with Ada.Long_Long_Integer_Text_IO;
with Ada.Containers.Vectors;

procedure Solution is

   use Ada.Text_IO;
   use Ada.Integer_Text_IO;
   use Ada.Long_Long_Integer_Text_IO;

   Inf : constant Long_Long_Integer := 1_000_000_000_000_000_000;

   --  Edge record for adjacency list
   type Edge is record
      To     : Integer;
      Weight : Long_Long_Integer;
   end record;

   package Edge_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Edge);

   --  Adjacency list: array of edge vectors, indexed 1 .. N
   type Adj_Array is array (Positive range <>) of Edge_Vectors.Vector;

   --  Heap node: (distance, node) pair
   type HeapNode is record
      Dist : Long_Long_Integer;
      Node : Integer;
   end record;

   --  Binary min-heap implemented with a dynamic array
   type Heap_Data is array (Positive range <>) of HeapNode;
   type Heap_Data_Access is access Heap_Data;

   type MinHeap is record
      Data     : Heap_Data_Access;
      Size     : Natural;
      Capacity : Natural;
   end record;

   procedure Heap_Init (H : in out MinHeap; Cap : Positive) is
   begin
      H.Data     := new Heap_Data (1 .. Cap);
      H.Size     := 0;
      H.Capacity := Cap;
   end Heap_Init;

   procedure Heap_Grow (H : in out MinHeap) is
      New_Cap  : constant Positive := H.Capacity * 2;
      New_Data : constant Heap_Data_Access := new Heap_Data (1 .. New_Cap);
   begin
      New_Data (1 .. H.Size) := H.Data (1 .. H.Size);
      H.Data     := New_Data;
      H.Capacity := New_Cap;
   end Heap_Grow;

   procedure Heap_Push (H : in out MinHeap; N : Integer; D : Long_Long_Integer) is
      I      : Positive;
      Parent : Positive;
      Tmp    : HeapNode;
   begin
      if H.Size = H.Capacity then
         Heap_Grow (H);
      end if;
      H.Size := H.Size + 1;
      I := H.Size;
      H.Data (I) := (Dist => D, Node => N);
      --  Sift up
      while I > 1 loop
         Parent := I / 2;
         if H.Data (Parent).Dist > H.Data (I).Dist then
            Tmp := H.Data (Parent);
            H.Data (Parent) := H.Data (I);
            H.Data (I) := Tmp;
            I := Parent;
         else
            exit;
         end if;
      end loop;
   end Heap_Push;

   procedure Heap_Pop (H : in out MinHeap; Result : out HeapNode) is
      I        : Positive := 1;
      Smallest : Positive;
      Left     : Natural;
      Right    : Natural;
      Tmp      : HeapNode;
   begin
      Result := H.Data (1);
      H.Data (1) := H.Data (H.Size);
      H.Size := H.Size - 1;
      --  Sift down
      loop
         Smallest := I;
         Left  := 2 * I;
         Right := 2 * I + 1;
         if Left <= H.Size
           and then H.Data (Left).Dist < H.Data (Smallest).Dist
         then
            Smallest := Left;
         end if;
         if Right <= H.Size
           and then H.Data (Right).Dist < H.Data (Smallest).Dist
         then
            Smallest := Right;
         end if;
         if Smallest /= I then
            Tmp := H.Data (I);
            H.Data (I) := H.Data (Smallest);
            H.Data (Smallest) := Tmp;
            I := Smallest;
         else
            exit;
         end if;
      end loop;
   end Heap_Pop;

   N, M : Integer;

begin
   Get (N);
   Get (M);

   declare
      Adj  : Adj_Array (1 .. N);
      Dist : array (1 .. N) of Long_Long_Integer := (others => Inf);
      Heap : MinHeap;
      Cur  : HeapNode;
      U, V : Integer;
      W    : Long_Long_Integer;
      New_Dist : Long_Long_Integer;
   begin
      --  Read edges
      for I in 1 .. M loop
         Get (U);
         Get (V);
         Get (W);
         Adj (U).Append ((To => V, Weight => W));
      end loop;

      --  Initialize source
      Dist (1) := 0;
      Heap_Init (Heap, N + 1);
      Heap_Push (Heap, 1, 0);

      --  Dijkstra main loop
      while Heap.Size > 0 loop
         Heap_Pop (Heap, Cur);

         --  Lazy deletion: skip stale entries
         if Cur.Dist > Dist (Cur.Node) then
            goto Continue;
         end if;

         --  Early exit: reached target
         if Cur.Node = N then
            exit;
         end if;

         --  Relax neighbors
         for E of Adj (Cur.Node) loop
            New_Dist := Dist (Cur.Node) + E.Weight;
            if New_Dist < Dist (E.To) then
               Dist (E.To) := New_Dist;
               Heap_Push (Heap, E.To, New_Dist);
            end if;
         end loop;

         <<Continue>>
         null;
      end loop;

      --  Output result
      if Dist (N) >= Inf then
         Put_Line ("-1");
      else
         Put (Dist (N), Width => 0);
         New_Line;
      end if;
   end;
end Solution;
