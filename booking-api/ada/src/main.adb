-- Booking API — Ada implementation using AWS, GNAT.SHA256, and Ada_Sqlite3
-- JWT HS256 signing/validation implemented manually using GNAT.SHA256 HMAC.
-- Compile: cd ada && alr build
-- Run:     cd ada && ./bin/main

with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams;                use Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;      use Ada.Strings.Unbounded;
with Ada.Text_IO;

with AWS.Config;
with AWS.Config.Set;
with AWS.Headers;
with AWS.Messages;
with AWS.Parameters;
with AWS.Response;
with AWS.Server;
with AWS.Status;

with Ada_Sqlite3;
with GNAT.SHA256;

procedure Main is

   use type Ada_Sqlite3.Result_Code;
   use type AWS.Status.Request_Method;

   LF : constant Character := Ada.Characters.Latin_1.LF;

   JWT_Secret : constant String := "booking-api-secret-key-2026";

   type Database_Access is access Ada_Sqlite3.Database;
   DB_Ptr : Database_Access;
   WS     : AWS.Server.HTTP;

   ---------------------------------------------------------------------------
   -- Base64url encoding/decoding (RFC 4648 §5, no padding)
   ---------------------------------------------------------------------------

   B64_Chars : constant String :=
     "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

   function Base64url_Encode (Input : String) return String is
      Result : Unbounded_String;
      I      : Positive := Input'First;
      A, B, C : Natural;
   begin
      while I <= Input'Last loop
         A := Character'Pos (Input (I));
         if I + 1 <= Input'Last then
            B := Character'Pos (Input (I + 1));
         else
            B := 0;
         end if;
         if I + 2 <= Input'Last then
            C := Character'Pos (Input (I + 2));
         else
            C := 0;
         end if;

         Append (Result, B64_Chars (A / 4 + 1));
         Append (Result, B64_Chars (((A mod 4) * 16 + B / 16) + 1));

         if I + 1 <= Input'Last then
            Append (Result, B64_Chars (((B mod 16) * 4 + C / 64) + 1));
         end if;

         if I + 2 <= Input'Last then
            Append (Result, B64_Chars (C mod 64 + 1));
         end if;

         I := I + 3;
      end loop;
      return To_String (Result);
   end Base64url_Encode;

   function Base64url_Encode_SEA
     (Input : Stream_Element_Array) return String
   is
      S : String (1 .. Input'Length);
   begin
      for I in Input'Range loop
         S (Integer (I - Input'First + 1)) :=
           Character'Val (Integer (Input (I)));
      end loop;
      return Base64url_Encode (S);
   end Base64url_Encode_SEA;

   function B64_Decode_Char (Ch : Character) return Natural is
   begin
      case Ch is
         when 'A' .. 'Z' => return Character'Pos (Ch) - Character'Pos ('A');
         when 'a' .. 'z' => return Character'Pos (Ch) - Character'Pos ('a') + 26;
         when '0' .. '9' => return Character'Pos (Ch) - Character'Pos ('0') + 52;
         when '-'         => return 62;
         when '_'         => return 63;
         when others      => return 0;
      end case;
   end B64_Decode_Char;

   function Base64url_Decode (Input : String) return String is
      Result : Unbounded_String;
      I      : Positive := Input'First;
      A, B, C, D : Natural;
   begin
      while I <= Input'Last loop
         A := B64_Decode_Char (Input (I));
         B := (if I + 1 <= Input'Last then B64_Decode_Char (Input (I + 1))
               else 0);
         C := (if I + 2 <= Input'Last then B64_Decode_Char (Input (I + 2))
               else 0);
         D := (if I + 3 <= Input'Last then B64_Decode_Char (Input (I + 3))
               else 0);

         Append (Result, Character'Val (A * 4 + B / 16));

         if I + 2 <= Input'Last then
            Append (Result, Character'Val ((B mod 16) * 16 + C / 4));
         end if;

         if I + 3 <= Input'Last then
            Append (Result, Character'Val ((C mod 4) * 64 + D));
         end if;

         I := I + 4;
      end loop;
      return To_String (Result);
   end Base64url_Decode;

   ---------------------------------------------------------------------------
   -- HMAC-SHA256 for JWT
   ---------------------------------------------------------------------------

   function HMAC_SHA256 (Key, Data : String)
     return GNAT.SHA256.Binary_Message_Digest
   is
      Ctx : GNAT.SHA256.Context := GNAT.SHA256.HMAC_Initial_Context (Key);
   begin
      GNAT.SHA256.Update (Ctx, Data);
      return GNAT.SHA256.Digest (Ctx);
   end HMAC_SHA256;

   ---------------------------------------------------------------------------
   -- Utility functions (must be before JWT helpers)
   ---------------------------------------------------------------------------

   function Int_Image (V : Integer) return String is
      S : constant String := Integer'Image (V);
   begin
      if S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end Int_Image;

   function Long_Image (V : Long_Integer) return String is
      S : constant String := Long_Integer'Image (V);
   begin
      if S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end Long_Image;

   ---------------------------------------------------------------------------
   -- JWT helpers (HS256)
   ---------------------------------------------------------------------------

   function Create_Token (User_Id : Integer) return String is
      Header_JSON  : constant String :=
        "{""alg"":""HS256"",""typ"":""JWT""}";
      Payload_JSON : constant String :=
        "{""user_id"":" & Int_Image (User_Id) &
        ",""exp"":9999999999}";
      Header_B64   : constant String := Base64url_Encode (Header_JSON);
      Payload_B64  : constant String := Base64url_Encode (Payload_JSON);
      Signing_Input : constant String := Header_B64 & "." & Payload_B64;
      Sig_Bytes    : constant GNAT.SHA256.Binary_Message_Digest :=
        HMAC_SHA256 (JWT_Secret, Signing_Input);
      Sig_B64      : constant String := Base64url_Encode_SEA (Sig_Bytes);
   begin
      return Signing_Input & "." & Sig_B64;
   end Create_Token;

   function Extract_User_Id (Request : AWS.Status.Data) return Integer is
      Hdrs     : constant AWS.Headers.List := AWS.Status.Header (Request);
      Auth_Hdr : constant String := Hdrs.Get ("Authorization");
      Prefix   : constant String := "Bearer ";
   begin
      if Auth_Hdr'Length <= Prefix'Length then
         return -1;
      end if;
      if Auth_Hdr (Auth_Hdr'First .. Auth_Hdr'First + Prefix'Length - 1) /=
        Prefix
      then
         return -1;
      end if;

      declare
         Token_Str : constant String :=
           Auth_Hdr (Auth_Hdr'First + Prefix'Length .. Auth_Hdr'Last);
         Dot1      : Natural := 0;
         Dot2      : Natural := 0;
      begin
         -- Find the two dots
         for I in Token_Str'Range loop
            if Token_Str (I) = '.' then
               if Dot1 = 0 then
                  Dot1 := I;
               else
                  Dot2 := I;
                  exit;
               end if;
            end if;
         end loop;

         if Dot1 = 0 or else Dot2 = 0 then
            return -1;
         end if;

         -- Verify signature
         declare
            Signing_Input : constant String :=
              Token_Str (Token_Str'First .. Dot2 - 1);
            Expected_Sig  : constant GNAT.SHA256.Binary_Message_Digest :=
              HMAC_SHA256 (JWT_Secret, Signing_Input);
            Expected_B64  : constant String :=
              Base64url_Encode_SEA (Expected_Sig);
            Actual_B64    : constant String :=
              Token_Str (Dot2 + 1 .. Token_Str'Last);
         begin
            if Expected_B64 /= Actual_B64 then
               return -1;
            end if;
         end;

         -- Decode payload and extract user_id
         declare
            Payload_B64 : constant String :=
              Token_Str (Dot1 + 1 .. Dot2 - 1);
            Payload_Str : constant String := Base64url_Decode (Payload_B64);
            Key         : constant String := """user_id"":";
            Pos         : Natural;
         begin
            Pos := Ada.Strings.Fixed.Index (Payload_Str, Key);
            if Pos = 0 then
               return -1;
            end if;
            declare
               Start : constant Positive := Pos + Key'Length;
               Fin   : Natural := Start;
            begin
               while Fin <= Payload_Str'Last
                 and then Payload_Str (Fin) in '0' .. '9'
               loop
                  Fin := Fin + 1;
               end loop;
               if Fin = Start then
                  return -1;
               end if;
               return Integer'Value (Payload_Str (Start .. Fin - 1));
            end;
         end;
      end;
   exception
      when others =>
         return -1;
   end Extract_User_Id;

   ---------------------------------------------------------------------------
   -- Utility functions
   ---------------------------------------------------------------------------

   function Hash_Password (Password : String) return String is
   begin
      return GNAT.SHA256.Digest ("booking-salt:" & Password);
   end Hash_Password;

   function Verify_Password (Password, Hash : String) return Boolean is
   begin
      return Hash_Password (Password) = Hash;
   end Verify_Password;

   function Float_Image (V : Float) return String is
      S      : constant String := Float'Image (V);
      Result : Unbounded_String;
      Dot_Pos      : Natural := 0;
      Last_Nonzero : Natural := 0;
   begin
      for I in S'Range loop
         if S (I) /= ' ' then
            Append (Result, S (I));
            declare
               Len : constant Natural := Length (Result);
            begin
               if S (I) = '.' then
                  Dot_Pos := Len;
               end if;
               if Dot_Pos > 0 and then S (I) /= '0' then
                  Last_Nonzero := Len;
               end if;
            end;
         end if;
      end loop;

      declare
         R : constant String := To_String (Result);
      begin
         if Dot_Pos = 0 then
            return R & ".0";
         end if;
         -- Keep at least one decimal digit
         if Last_Nonzero <= Dot_Pos then
            return R (R'First .. Dot_Pos + 1);
         end if;
         return R (R'First .. Last_Nonzero);
      end;
   end Float_Image;

   function Escape_JSON (S : String) return String is
      Result : Unbounded_String;
   begin
      for I in S'Range loop
         case S (I) is
            when '"'  => Append (Result, "\""");
            when '\'  => Append (Result, "\\");
            when others =>
               if Character'Pos (S (I)) < 32 then
                  Append (Result, " ");
               else
                  Append (Result, S (I));
               end if;
         end case;
      end loop;
      return To_String (Result);
   end Escape_JSON;

   ---------------------------------------------------------------------------
   -- Simple JSON parsing (extract values from flat JSON objects)
   ---------------------------------------------------------------------------

   function JSON_Get_String (Src : String; Key : String) return String is
      Search : constant String := """" & Key & """:""";
      Pos    : Natural;
   begin
      Pos := Ada.Strings.Fixed.Index (Src, Search);
      if Pos = 0 then
         return "";
      end if;
      declare
         Start : constant Positive := Pos + Search'Length;
         Fin   : Natural := Start;
      begin
         while Fin <= Src'Last and then Src (Fin) /= '"' loop
            if Src (Fin) = '\' and then Fin + 1 <= Src'Last then
               Fin := Fin + 2;
            else
               Fin := Fin + 1;
            end if;
         end loop;
         return Src (Start .. Fin - 1);
      end;
   end JSON_Get_String;

   function JSON_Get_Number (Src : String; Key : String) return String is
      Search : constant String := """" & Key & """:";
      Pos    : Natural;
   begin
      Pos := Ada.Strings.Fixed.Index (Src, Search);
      if Pos = 0 then
         return "";
      end if;
      declare
         Start : Positive := Pos + Search'Length;
         Fin   : Natural;
      begin
         while Start <= Src'Last and then Src (Start) = ' ' loop
            Start := Start + 1;
         end loop;
         Fin := Start;
         while Fin <= Src'Last
           and then Src (Fin) in '0' .. '9' | '.' | '-' | '+' | 'e' | 'E'
         loop
            Fin := Fin + 1;
         end loop;
         if Fin = Start then
            return "";
         end if;
         return Src (Start .. Fin - 1);
      end;
   end JSON_Get_Number;

   function JSON_Has_Key (Src : String; Key : String) return Boolean is
      Search : constant String := """" & Key & """:";
   begin
      return Ada.Strings.Fixed.Index (Src, Search) > 0;
   end JSON_Has_Key;

   ---------------------------------------------------------------------------
   -- SQL row to JSON helpers
   ---------------------------------------------------------------------------

   function User_JSON (Stmt : Ada_Sqlite3.Statement) return String is
   begin
      return "{""id"":" & Long_Image (Stmt.Column_Int64 (0)) &
             ",""email"":""" & Escape_JSON (Stmt.Column_Text (1)) &
             """,""name"":""" & Escape_JSON (Stmt.Column_Text (2)) & """}";
   end User_JSON;

   function Space_JSON (Stmt : Ada_Sqlite3.Statement) return String is
      Desc : constant String := (if Stmt.Column_Is_Null (2) then ""
                                 else Stmt.Column_Text (2));
   begin
      return "{""id"":" & Long_Image (Stmt.Column_Int64 (0)) &
             ",""name"":""" & Escape_JSON (Stmt.Column_Text (1)) &
             """,""description"":" &
             (if Desc = "" then "null"
              else """" & Escape_JSON (Desc) & """") &
             ",""price_per_hour"":" & Float_Image (Stmt.Column_Double (3)) &
             ",""owner_id"":" & Long_Image (Stmt.Column_Int64 (4)) &
             ",""created_at"":""" & Escape_JSON (Stmt.Column_Text (5)) &
             """}";
   end Space_JSON;

   function Booking_JSON (Stmt : Ada_Sqlite3.Statement) return String is
   begin
      return "{""id"":" & Long_Image (Stmt.Column_Int64 (0)) &
             ",""space_id"":" & Long_Image (Stmt.Column_Int64 (1)) &
             ",""user_id"":" & Long_Image (Stmt.Column_Int64 (2)) &
             ",""start_time"":""" & Escape_JSON (Stmt.Column_Text (3)) &
             """,""end_time"":""" & Escape_JSON (Stmt.Column_Text (4)) &
             """,""status"":""" & Escape_JSON (Stmt.Column_Text (5)) &
             """,""created_at"":""" & Escape_JSON (Stmt.Column_Text (6)) &
             """}";
   end Booking_JSON;

   ---------------------------------------------------------------------------
   -- JSON response builders
   ---------------------------------------------------------------------------

   function JSON_Response
     (Status : AWS.Messages.Status_Code;
      Msg    : String) return AWS.Response.Data
   is
   begin
      return AWS.Response.Build
        (Content_Type => "application/json",
         Message_Body => Msg,
         Status_Code  => Status);
   end JSON_Response;

   function Error_JSON
     (Status : AWS.Messages.Status_Code;
      Msg    : String) return AWS.Response.Data
   is
   begin
      return JSON_Response (Status, "{""error"":""" & Msg & """}");
   end Error_JSON;

   ---------------------------------------------------------------------------
   -- Route handlers
   ---------------------------------------------------------------------------

   function Handle_Register (Request : AWS.Status.Data)
     return AWS.Response.Data
   is
      Body_Str : constant String :=
        To_String (AWS.Status.Binary_Data (Request));
      Email    : constant String := JSON_Get_String (Body_Str, "email");
      Name     : constant String := JSON_Get_String (Body_Str, "name");
      Password : constant String := JSON_Get_String (Body_Str, "password");
   begin
      if Email = "" or else Name = "" or else Password = "" then
         return Error_JSON (AWS.Messages.S400, "missing required fields");
      end if;

      declare
         Check_Stmt : Ada_Sqlite3.Statement :=
           DB_Ptr.Prepare ("SELECT id FROM users WHERE email = ?1");
         RC : Ada_Sqlite3.Result_Code;
      begin
         Check_Stmt.Bind_Text (1, Email);
         RC := Check_Stmt.Step;
         if RC = Ada_Sqlite3.ROW then
            return Error_JSON (AWS.Messages.S409, "email already exists");
         end if;
      end;

      declare
         Hash     : constant String := Hash_Password (Password);
         Ins_Stmt : Ada_Sqlite3.Statement :=
           DB_Ptr.Prepare ("INSERT INTO users (email, name, password_hash) " &
                       "VALUES (?1, ?2, ?3)");
      begin
         Ins_Stmt.Bind_Text (1, Email);
         Ins_Stmt.Bind_Text (2, Name);
         Ins_Stmt.Bind_Text (3, Hash);
         Ins_Stmt.Step;
      end;

      declare
         New_Id   : constant Long_Integer := DB_Ptr.Last_Insert_Row_ID;
         Sel_Stmt : Ada_Sqlite3.Statement :=
           DB_Ptr.Prepare ("SELECT id, email, name FROM users WHERE id = ?1");
         RC : Ada_Sqlite3.Result_Code;
      begin
         Sel_Stmt.Bind_Int64 (1, New_Id);
         RC := Sel_Stmt.Step;
         if RC = Ada_Sqlite3.ROW then
            return JSON_Response (AWS.Messages.S201, User_JSON (Sel_Stmt));
         end if;
      end;

      return Error_JSON (AWS.Messages.S500, "internal error");
   exception
      when Ada_Sqlite3.SQLite_Error =>
         return Error_JSON (AWS.Messages.S409, "email already exists");
   end Handle_Register;

   function Handle_Login (Request : AWS.Status.Data)
     return AWS.Response.Data
   is
      Body_Str : constant String :=
        To_String (AWS.Status.Binary_Data (Request));
      Email    : constant String := JSON_Get_String (Body_Str, "email");
      Password : constant String := JSON_Get_String (Body_Str, "password");
   begin
      if Email = "" or else Password = "" then
         return Error_JSON (AWS.Messages.S401, "invalid credentials");
      end if;

      declare
         Stmt : Ada_Sqlite3.Statement :=
           DB_Ptr.Prepare ("SELECT id, email, name, password_hash " &
                       "FROM users WHERE email = ?1");
         RC : Ada_Sqlite3.Result_Code;
      begin
         Stmt.Bind_Text (1, Email);
         RC := Stmt.Step;
         if RC /= Ada_Sqlite3.ROW then
            return Error_JSON (AWS.Messages.S401, "invalid credentials");
         end if;

         declare
            User_Id : constant Integer := Stmt.Column_Int (0);
            U_Email : constant String  := Stmt.Column_Text (1);
            U_Name  : constant String  := Stmt.Column_Text (2);
            PW_Hash : constant String  := Stmt.Column_Text (3);
         begin
            if not Verify_Password (Password, PW_Hash) then
               return Error_JSON (AWS.Messages.S401, "invalid credentials");
            end if;

            declare
               Token : constant String := Create_Token (User_Id);
            begin
               return JSON_Response (AWS.Messages.S200,
                 "{""token"":""" & Token &
                 """,""user"":{""id"":" & Int_Image (User_Id) &
                 ",""email"":""" & Escape_JSON (U_Email) &
                 """,""name"":""" & Escape_JSON (U_Name) & """}}");
            end;
         end;
      end;
   end Handle_Login;

   function Handle_List_Spaces (Request : AWS.Status.Data)
     return AWS.Response.Data
   is
      Params : constant AWS.Parameters.List :=
        AWS.Status.Parameters (Request);

      SQL        : Unbounded_String :=
        To_Unbounded_String ("SELECT id, name, description, " &
          "price_per_hour, owner_id, created_at FROM spaces WHERE 1=1");
      Bind_Count : Natural := 0;

      type Bind_Entry is record
         Is_Float : Boolean := False;
         F_Val    : Float   := 0.0;
         S_Val    : Unbounded_String;
      end record;

      Binds : array (1 .. 4) of Bind_Entry;

      Min_P : constant String := Params.Get ("min_price");
      Max_P : constant String := Params.Get ("max_price");
      Avail : constant String := Params.Get ("available_at");
   begin
      if Min_P /= "" then
         Bind_Count := Bind_Count + 1;
         Append (SQL, " AND price_per_hour >= ?" &
                 Int_Image (Bind_Count));
         Binds (Bind_Count) := (Is_Float => True,
                                F_Val    => Float'Value (Min_P),
                                S_Val    => Null_Unbounded_String);
      end if;

      if Max_P /= "" then
         Bind_Count := Bind_Count + 1;
         Append (SQL, " AND price_per_hour <= ?" &
                 Int_Image (Bind_Count));
         Binds (Bind_Count) := (Is_Float => True,
                                F_Val    => Float'Value (Max_P),
                                S_Val    => Null_Unbounded_String);
      end if;

      if Avail /= "" then
         Bind_Count := Bind_Count + 1;
         declare
            Idx1 : constant String := Int_Image (Bind_Count);
         begin
            Bind_Count := Bind_Count + 1;
            declare
               Idx2 : constant String := Int_Image (Bind_Count);
            begin
               Append (SQL, " AND id NOT IN (SELECT space_id FROM bookings" &
                       " WHERE status IN ('pending','confirmed')" &
                       " AND start_time < ?" & Idx1 &
                       " AND end_time > ?" & Idx2 & ")");
               Binds (Bind_Count - 1) :=
                 (False, 0.0, To_Unbounded_String (Avail));
               Binds (Bind_Count) :=
                 (False, 0.0, To_Unbounded_String (Avail));
            end;
         end;
      end if;

      declare
         Stmt   : Ada_Sqlite3.Statement := DB_Ptr.Prepare (To_String (SQL));
         Result : Unbounded_String := To_Unbounded_String ("[");
         First  : Boolean := True;
         RC     : Ada_Sqlite3.Result_Code;
      begin
         for I in 1 .. Bind_Count loop
            if Binds (I).Is_Float then
               Stmt.Bind_Double (I, Binds (I).F_Val);
            else
               Stmt.Bind_Text (I, To_String (Binds (I).S_Val));
            end if;
         end loop;

         loop
            RC := Stmt.Step;
            exit when RC /= Ada_Sqlite3.ROW;
            if not First then
               Append (Result, ",");
            end if;
            First := False;
            Append (Result, Space_JSON (Stmt));
         end loop;

         Append (Result, "]");
         return JSON_Response (AWS.Messages.S200, To_String (Result));
      end;
   end Handle_List_Spaces;

   function Handle_Create_Space (Request : AWS.Status.Data)
     return AWS.Response.Data
   is
      User_Id : constant Integer := Extract_User_Id (Request);
   begin
      if User_Id < 0 then
         return Error_JSON (AWS.Messages.S401, "unauthorized");
      end if;

      declare
         Body_Str : constant String :=
           To_String (AWS.Status.Binary_Data (Request));
         Name     : constant String := JSON_Get_String (Body_Str, "name");
      begin
         if Name = "" or else not JSON_Has_Key (Body_Str, "price_per_hour")
         then
            return Error_JSON (AWS.Messages.S400, "missing required fields");
         end if;

         declare
            Price_Str : constant String :=
              JSON_Get_Number (Body_Str, "price_per_hour");
            Price : constant Float := Float'Value (Price_Str);
            Desc  : constant String :=
              JSON_Get_String (Body_Str, "description");
            Stmt  : Ada_Sqlite3.Statement :=
              DB_Ptr.Prepare ("INSERT INTO spaces " &
                "(name, description, price_per_hour, owner_id) " &
                "VALUES (?1, ?2, ?3, ?4)");
         begin
            Stmt.Bind_Text (1, Name);
            if Desc = "" then
               Stmt.Bind_Null (2);
            else
               Stmt.Bind_Text (2, Desc);
            end if;
            Stmt.Bind_Double (3, Price);
            Stmt.Bind_Int (4, User_Id);
            Stmt.Step;
         end;

         declare
            New_Id   : constant Long_Integer := DB_Ptr.Last_Insert_Row_ID;
            Sel_Stmt : Ada_Sqlite3.Statement :=
              DB_Ptr.Prepare ("SELECT id, name, description, price_per_hour, " &
                          "owner_id, created_at FROM spaces WHERE id = ?1");
            RC : Ada_Sqlite3.Result_Code;
         begin
            Sel_Stmt.Bind_Int64 (1, New_Id);
            RC := Sel_Stmt.Step;
            if RC = Ada_Sqlite3.ROW then
               return JSON_Response (AWS.Messages.S201,
                                     Space_JSON (Sel_Stmt));
            end if;
         end;

         return Error_JSON (AWS.Messages.S500, "internal error");
      end;
   end Handle_Create_Space;

   function Handle_Create_Booking (Request : AWS.Status.Data)
     return AWS.Response.Data
   is
      User_Id : constant Integer := Extract_User_Id (Request);
   begin
      if User_Id < 0 then
         return Error_JSON (AWS.Messages.S401, "unauthorized");
      end if;

      declare
         Body_Str   : constant String :=
           To_String (AWS.Status.Binary_Data (Request));
         Space_Str  : constant String :=
           JSON_Get_Number (Body_Str, "space_id");
         Start_Time : constant String :=
           JSON_Get_String (Body_Str, "start_time");
         End_Time   : constant String :=
           JSON_Get_String (Body_Str, "end_time");
      begin
         if Space_Str = "" or else Start_Time = "" or else End_Time = "" then
            return Error_JSON (AWS.Messages.S400, "missing required fields");
         end if;

         declare
            Space_Id : constant Integer := Integer'Value (Space_Str);
         begin
            -- Check space exists
            declare
               Check : Ada_Sqlite3.Statement :=
                 DB_Ptr.Prepare ("SELECT id FROM spaces WHERE id = ?1");
               RC : Ada_Sqlite3.Result_Code;
            begin
               Check.Bind_Int (1, Space_Id);
               RC := Check.Step;
               if RC /= Ada_Sqlite3.ROW then
                  return Error_JSON (AWS.Messages.S404, "space not found");
               end if;
            end;

            -- Check overlap
            declare
               Ovlp : Ada_Sqlite3.Statement :=
                 DB_Ptr.Prepare ("SELECT id FROM bookings WHERE space_id = ?1" &
                   " AND status IN ('pending','confirmed')" &
                   " AND start_time < ?3 AND end_time > ?2");
               RC : Ada_Sqlite3.Result_Code;
            begin
               Ovlp.Bind_Int (1, Space_Id);
               Ovlp.Bind_Text (2, Start_Time);
               Ovlp.Bind_Text (3, End_Time);
               RC := Ovlp.Step;
               if RC = Ada_Sqlite3.ROW then
                  return Error_JSON (AWS.Messages.S409, "booking overlap");
               end if;
            end;

            -- Insert
            declare
               Ins : Ada_Sqlite3.Statement :=
                 DB_Ptr.Prepare ("INSERT INTO bookings " &
                   "(space_id, user_id, start_time, end_time, status) " &
                   "VALUES (?1, ?2, ?3, ?4, 'confirmed')");
            begin
               Ins.Bind_Int (1, Space_Id);
               Ins.Bind_Int (2, User_Id);
               Ins.Bind_Text (3, Start_Time);
               Ins.Bind_Text (4, End_Time);
               Ins.Step;
            end;

            declare
               New_Id : constant Long_Integer := DB_Ptr.Last_Insert_Row_ID;
               Sel    : Ada_Sqlite3.Statement :=
                 DB_Ptr.Prepare ("SELECT id, space_id, user_id, start_time, " &
                             "end_time, status, created_at " &
                             "FROM bookings WHERE id = ?1");
               RC : Ada_Sqlite3.Result_Code;
            begin
               Sel.Bind_Int64 (1, New_Id);
               RC := Sel.Step;
               if RC = Ada_Sqlite3.ROW then
                  return JSON_Response (AWS.Messages.S201,
                                        Booking_JSON (Sel));
               end if;
            end;

            return Error_JSON (AWS.Messages.S500, "internal error");
         end;
      end;
   end Handle_Create_Booking;

   function Handle_My_Bookings (Request : AWS.Status.Data)
     return AWS.Response.Data
   is
      User_Id : constant Integer := Extract_User_Id (Request);
   begin
      if User_Id < 0 then
         return Error_JSON (AWS.Messages.S401, "unauthorized");
      end if;

      declare
         Stmt   : Ada_Sqlite3.Statement :=
           DB_Ptr.Prepare ("SELECT id, space_id, user_id, start_time, " &
                       "end_time, status, created_at " &
                       "FROM bookings WHERE user_id = ?1");
         Result : Unbounded_String := To_Unbounded_String ("[");
         First  : Boolean := True;
         RC     : Ada_Sqlite3.Result_Code;
      begin
         Stmt.Bind_Int (1, User_Id);
         loop
            RC := Stmt.Step;
            exit when RC /= Ada_Sqlite3.ROW;
            if not First then
               Append (Result, ",");
            end if;
            First := False;
            Append (Result, Booking_JSON (Stmt));
         end loop;

         Append (Result, "]");
         return JSON_Response (AWS.Messages.S200, To_String (Result));
      end;
   end Handle_My_Bookings;

   function Handle_Cancel_Booking
     (Request    : AWS.Status.Data;
      Booking_Id : Integer) return AWS.Response.Data
   is
      User_Id : constant Integer := Extract_User_Id (Request);
   begin
      if User_Id < 0 then
         return Error_JSON (AWS.Messages.S401, "unauthorized");
      end if;

      declare
         Stmt : Ada_Sqlite3.Statement :=
           DB_Ptr.Prepare ("SELECT id, space_id, user_id, start_time, " &
                       "end_time, status, created_at " &
                       "FROM bookings WHERE id = ?1");
         RC : Ada_Sqlite3.Result_Code;
      begin
         Stmt.Bind_Int (1, Booking_Id);
         RC := Stmt.Step;
         if RC /= Ada_Sqlite3.ROW then
            return Error_JSON (AWS.Messages.S404, "booking not found");
         end if;

         declare
            Owner_Id : constant Integer := Stmt.Column_Int (2);
         begin
            if Owner_Id /= User_Id then
               return Error_JSON (AWS.Messages.S403, "forbidden");
            end if;
         end;
      end;

      declare
         Upd : Ada_Sqlite3.Statement :=
           DB_Ptr.Prepare ("UPDATE bookings SET status = 'cancelled' " &
                       "WHERE id = ?1");
      begin
         Upd.Bind_Int (1, Booking_Id);
         Upd.Step;
      end;

      declare
         Sel : Ada_Sqlite3.Statement :=
           DB_Ptr.Prepare ("SELECT id, space_id, user_id, start_time, " &
                       "end_time, status, created_at " &
                       "FROM bookings WHERE id = ?1");
         RC : Ada_Sqlite3.Result_Code;
      begin
         Sel.Bind_Int (1, Booking_Id);
         RC := Sel.Step;
         if RC = Ada_Sqlite3.ROW then
            return JSON_Response (AWS.Messages.S200, Booking_JSON (Sel));
         end if;
      end;

      return Error_JSON (AWS.Messages.S500, "internal error");
   end Handle_Cancel_Booking;

   ---------------------------------------------------------------------------
   -- Main callback / router
   ---------------------------------------------------------------------------

   function Router (Request : AWS.Status.Data) return AWS.Response.Data is
      URI_Str : constant String := AWS.Status.URI (Request);
      Method  : constant AWS.Status.Request_Method :=
        AWS.Status.Method (Request);
   begin
      if Method = AWS.Status.POST and then URI_Str = "/api/auth/register" then
         return Handle_Register (Request);
      end if;

      if Method = AWS.Status.POST and then URI_Str = "/api/auth/login" then
         return Handle_Login (Request);
      end if;

      if Method = AWS.Status.GET and then URI_Str = "/api/spaces" then
         return Handle_List_Spaces (Request);
      end if;

      if Method = AWS.Status.POST and then URI_Str = "/api/spaces" then
         return Handle_Create_Space (Request);
      end if;

      if Method = AWS.Status.GET and then URI_Str = "/api/bookings/my" then
         return Handle_My_Bookings (Request);
      end if;

      if Method = AWS.Status.POST and then URI_Str = "/api/bookings" then
         return Handle_Create_Booking (Request);
      end if;

      if Method = AWS.Status.DELETE then
         declare
            Prefix : constant String := "/api/bookings/";
         begin
            if URI_Str'Length > Prefix'Length
              and then URI_Str (URI_Str'First ..
                                URI_Str'First + Prefix'Length - 1) = Prefix
            then
               declare
                  Id_Str : constant String :=
                    URI_Str (URI_Str'First + Prefix'Length .. URI_Str'Last);
               begin
                  return Handle_Cancel_Booking
                    (Request, Integer'Value (Id_Str));
               end;
            end if;
         end;
      end if;

      return Error_JSON (AWS.Messages.S404, "not found");
   exception
      when others =>
         return Error_JSON (AWS.Messages.S500, "internal error");
   end Router;

   ---------------------------------------------------------------------------
   -- Database initialization
   ---------------------------------------------------------------------------

   procedure Init_Database is
      CWD_Schema  : constant String :=
        Ada.Directories.Current_Directory & "/schema.sql";
      Exe_Schema  : constant String :=
        Ada.Directories.Containing_Directory
          (Ada.Directories.Containing_Directory
             (Ada.Command_Line.Command_Name)) & "/../schema.sql";
      Actual_Path : constant String :=
        (if Ada.Directories.Exists (CWD_Schema) then CWD_Schema
         elsif Ada.Directories.Exists (Exe_Schema) then Exe_Schema
         else CWD_Schema);
      File   : Ada.Text_IO.File_Type;
      Schema : Unbounded_String;
      Line   : String (1 .. 4096);
      Last   : Natural;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Actual_Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Line, Last);
         Append (Schema, Line (1 .. Last));
         Append (Schema, LF);
      end loop;
      Ada.Text_IO.Close (File);

      DB_Ptr := new Ada_Sqlite3.Database'(Ada_Sqlite3.Open ("booking.db"));
      DB_Ptr.Execute ("PRAGMA journal_mode=WAL");
      DB_Ptr.Execute ("PRAGMA foreign_keys=ON");

      declare
         S   : constant String := To_String (Schema);
         Pos : Natural := S'First;
         Sem : Natural;
      begin
         while Pos <= S'Last loop
            Sem := Ada.Strings.Fixed.Index (S, ";", Pos);
            exit when Sem = 0;
            declare
               Stmt_Text : constant String :=
                 Ada.Strings.Fixed.Trim (S (Pos .. Sem), Ada.Strings.Both);
            begin
               if Stmt_Text'Length > 1 then
                  DB_Ptr.Execute (Stmt_Text);
               end if;
            end;
            Pos := Sem + 1;
         end loop;
      end;
   end Init_Database;

   ---------------------------------------------------------------------------
   -- Main
   ---------------------------------------------------------------------------

   Cfg : AWS.Config.Object;

begin
   Init_Database;

   AWS.Config.Set.Server_Port (Cfg, 8080);
   AWS.Config.Set.Server_Name (Cfg, "Booking API");
   AWS.Config.Set.Max_Connection (Cfg, 10);
   AWS.Config.Set.Reuse_Address (Cfg, True);

   AWS.Server.Start
     (WS, Callback => Router'Unrestricted_Access, Config => Cfg);

   Ada.Text_IO.Put_Line ("Booking API listening on port 8080");

   AWS.Server.Wait (AWS.Server.Forever);
end Main;
