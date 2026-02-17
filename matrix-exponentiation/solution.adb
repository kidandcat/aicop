--
--  Compute N-th Fibonacci number mod 10^9+7 using matrix exponentiation.
--  F(0) = 0, F(1) = 1, F(N) = F(N-1) + F(N-2)
--
--  Uses the identity:
--    |F(n+1)  F(n)  |   |1 1|^n
--    |F(n)    F(n-1)| = |1 0|
--
--  Time: O(log N), Space: O(1)
--

with Ada.Text_IO;
with Ada.Long_Long_Integer_Text_IO;

procedure Solution is

   Modulus : constant Long_Long_Integer := 1_000_000_007;

   type Matrix_2x2 is array (0 .. 1, 0 .. 1) of Long_Long_Integer;

   function Mat_Mul (A, B : Matrix_2x2) return Matrix_2x2 is
      C : Matrix_2x2 := (others => (others => 0));
   begin
      for I in 0 .. 1 loop
         for J in 0 .. 1 loop
            for K in 0 .. 1 loop
               C (I, J) := (C (I, J) + (A (I, K) mod Modulus)
                            * (B (K, J) mod Modulus)) mod Modulus;
            end loop;
         end loop;
      end loop;
      return C;
   end Mat_Mul;

   function Mat_Pow (Base : Matrix_2x2;
                     Exp  : Long_Long_Integer) return Matrix_2x2 is
      Result : Matrix_2x2 := ((1, 0), (0, 1));  -- Identity matrix
      B      : Matrix_2x2 := Base;
      E      : Long_Long_Integer := Exp;
   begin
      while E > 0 loop
         if E mod 2 = 1 then
            Result := Mat_Mul (Result, B);
         end if;
         B := Mat_Mul (B, B);
         E := E / 2;
      end loop;
      return Result;
   end Mat_Pow;

   N      : Long_Long_Integer;
   Base   : Matrix_2x2;
   Result : Matrix_2x2;

begin
   Ada.Long_Long_Integer_Text_IO.Get (N);

   if N = 0 then
      Ada.Text_IO.Put_Line ("0");
      return;
   end if;

   Base := ((1, 1), (1, 0));

   Result := Mat_Pow (Base, N);

   --  F(N) is at Result(0, 1) (or Result(1, 0))
   Ada.Long_Long_Integer_Text_IO.Put (Result (0, 1), Width => 0);
   Ada.Text_IO.New_Line;
end Solution;
