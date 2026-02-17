--
--  KMP (Knuth-Morris-Pratt) string matching algorithm.
--  Finds all occurrences of pattern P in text T, including overlapping matches.
--
--  Time: O(N + M), Space: O(N + M) where N = |T|, M = |P|
--

with Ada.Text_IO;              use Ada.Text_IO;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

procedure Solution is

   package Natural_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Natural);
   use Natural_Vectors;

   --  Build the LPS (Longest Proper Prefix which is also Suffix) array
   function Build_LPS (Pattern : String) return Natural_Vectors.Vector is
      M   : constant Natural := Pattern'Length;
      LPS : Natural_Vectors.Vector;
      Len : Natural := 0;
      I   : Natural := 2;  -- 1-based; Pattern'First is 1
   begin
      LPS.Set_Length (Ada.Containers.Count_Type (M));
      if M = 0 then
         return LPS;
      end if;
      LPS.Replace_Element (0, 0);

      while I <= M loop
         if Pattern (I) = Pattern (Len + 1) then
            Len := Len + 1;
            LPS.Replace_Element (I - 1, Len);
            I := I + 1;
         else
            if Len /= 0 then
               Len := LPS.Element (Len - 1);
            else
               LPS.Replace_Element (I - 1, 0);
               I := I + 1;
            end if;
         end if;
      end loop;

      return LPS;
   end Build_LPS;

   --  KMP search: find all occurrences of Pattern in Text
   function KMP_Search
     (Text    : String;
      Pattern : String;
      LPS     : Natural_Vectors.Vector) return Natural_Vectors.Vector
   is
      N       : constant Natural := Text'Length;
      M       : constant Natural := Pattern'Length;
      Matches : Natural_Vectors.Vector;
      I       : Natural := 1;  -- index in Text (1-based)
      J       : Natural := 0;  -- number of matched chars so far
   begin
      while I <= N loop
         if Text (I) = Pattern (J + 1) then
            I := I + 1;
            J := J + 1;
         end if;

         if J = M then
            --  Found a match; record 0-indexed position
            Matches.Append (I - M - 1);
            J := LPS.Element (J - 1);
         elsif I <= N and then Text (I) /= Pattern (J + 1) then
            if J /= 0 then
               J := LPS.Element (J - 1);
            else
               I := I + 1;
            end if;
         end if;
      end loop;

      return Matches;
   end KMP_Search;

   Text_Line    : constant Unbounded_String := To_Unbounded_String (Get_Line);
   Pattern_Line : constant Unbounded_String := To_Unbounded_String (Get_Line);

   T : constant String := To_String (Text_Line);
   P : constant String := To_String (Pattern_Line);

begin
   if P'Length = 0 or else T'Length = 0 or else P'Length > T'Length then
      Put_Line ("0");
      New_Line;
      return;
   end if;

   declare
      LPS     : constant Natural_Vectors.Vector := Build_LPS (P);
      Matches : constant Natural_Vectors.Vector := KMP_Search (T, P, LPS);
      Count   : constant Natural := Natural (Matches.Length);
   begin
      Put_Line (Natural'Image (Count)(2 .. Natural'Image (Count)'Last));

      if Count = 0 then
         New_Line;
      else
         for I in 0 .. Count - 1 loop
            if I > 0 then
               Put (' ');
            end if;
            declare
               Pos_Str : constant String := Natural'Image (Matches.Element (I));
            begin
               Put (Pos_Str (2 .. Pos_Str'Last));
            end;
         end loop;
         New_Line;
      end if;
   end;
end Solution;
