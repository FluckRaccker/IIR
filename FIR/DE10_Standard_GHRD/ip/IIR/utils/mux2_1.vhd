 library IEEE;
 use IEEE.STD_LOGIC_1164.all;
 
 entity mux2_1 is
    generic(n :positive:=16);
    Port ( A : in STD_LOGIC_VECTOR (n-1 downto 0);
           B : in STD_LOGIC_VECTOR (n-1 downto 0);
           Sel : in STD_LOGIC;
           S : out STD_LOGIC_VECTOR (n-1 downto 0));
 end mux2_1;
 
 architecture mux of mux2_1 is
 
 begin
      S <= A when Sel='0' else B;
 end mux;
 
