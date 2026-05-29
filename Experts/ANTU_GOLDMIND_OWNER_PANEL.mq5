//+------------------------------------------------------------------+
//|                         ANTU_GOLDMIND_OWNER_PANEL.mq5            |
//|        OWNER ONLY - License Key Generator + Admin Panel          |
//|        Yeh file sirf OWNER ke paas rahegi                        |
//|        Client ko yeh file KABHI mat dena!                        |
//+------------------------------------------------------------------+
#property copyright "ANTU Trading"
#property version   "1.00"
#property strict
#property description "OWNER ADMIN PANEL - Generate License Keys for Clients"
#property description "Admin Password se khulega, Client ka account number daalo, key milegi"

//================ ADMIN SETTINGS ===================//
input group "=== Admin Login ==="
input string   InpOwnerPassword      = "";       // Owner Password (required)
input long     InpClientAccount      = 0;        // Client Account Number (0 = current account)

//--- LICENSE CONSTANTS (same as main EA - MUST MATCH!)
#define LICENSE_OWNER_PASS    "ANTUOWNER2024"
#define LICENSE_SALT          "ANTU_GOLD_"

//--- Dashboard Colors
#define CLR_BG             C'18,18,22'
#define CLR_GOLD           C'212,175,55'
#define CLR_WHITE          C'250,250,255'
#define CLR_GREEN          C'0,220,110'
#define CLR_RED            C'255,70,70'
#define CLR_MUTED          C'140,145,150'

//+------------------------------------------------------------------+
//| Generate License Key (SAME algorithm as main EA)                 |
//+------------------------------------------------------------------+
string GenerateLicenseKey(long accountNum){
   string raw = LICENSE_SALT + IntegerToString(accountNum);
   int hash = 0;
   for(int i=0; i<StringLen(raw); i++){
      hash = hash * 31 + StringGetCharacter(raw, i);
      hash = hash % 999999;
   }
   if(hash < 0) hash = -hash;
   return "ANTU-" + IntegerToString(hash, 6, '0');
}

//+------------------------------------------------------------------+
//| Draw helpers                                                     |
//+------------------------------------------------------------------+
void DrawRect(string name,int x,int y,int w,int h,color bg){
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}

void DrawText(string name,int x,int y,string txt,int sz,color clr,string font="Segoe UI",bool bold=false){
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,sz);
   ObjectSetString(0,name,OBJPROP_FONT, bold ? font+" Bold" : font);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Show Admin Panel on Chart                                        |
//+------------------------------------------------------------------+
void ShowAdminPanel(long accNum, string key){
   // Outer frame
   DrawRect("ADM_Outer",30,30,350,280,CLR_GOLD);
   DrawRect("ADM_Inner",32,32,346,276,CLR_BG);
   DrawRect("ADM_Header",32,32,346,45,CLR_GOLD);
   
   DrawText("ADM_Title",55,40,"ANTU TRADING - OWNER PANEL",12,C'15,15,15',"Segoe UI Black",true);
   
   DrawRect("ADM_Line1",50,100,310,1,C'35,35,42');
   DrawRect("ADM_Line2",50,200,310,1,C'35,35,42');
   
   DrawText("ADM_L1",50,85,"ACCOUNT NUMBER",9,CLR_MUTED,"Segoe UI",true);
   DrawText("ADM_V1",50,110,IntegerToString(accNum),18,CLR_WHITE,"Consolas",true);
   
   DrawText("ADM_L2",50,145,"LICENSE KEY",9,CLR_MUTED,"Segoe UI",true);
   DrawText("ADM_V2",50,165,key,22,CLR_GREEN,"Consolas",true);
   
   DrawText("ADM_L3",50,210,"CLIENT PASSWORD",9,CLR_MUTED,"Segoe UI",true);
   DrawText("ADM_V3",50,230,"ANTU2024PRO",14,CLR_WHITE,"Consolas",true);
   
   DrawText("ADM_L4",50,258,"TRIAL DAYS",9,CLR_MUTED,"Segoe UI",true);
   DrawText("ADM_V4",200,258,"7 days (auto)",10,CLR_MUTED,"Consolas",true);
   
   DrawText("ADM_Footer",100,285,"OWNER ONLY - DO NOT SHARE THIS FILE",7,CLR_RED,"Segoe UI",true);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit(){
   // PASSWORD CHECK
   if(InpOwnerPassword != LICENSE_OWNER_PASS){
      Alert("ACCESS DENIED! Invalid Owner Password.");
      Print("ERROR: Wrong owner password entered.");
      return(INIT_FAILED);
   }
   
   // Get account number
   long accNum = InpClientAccount;
   if(accNum == 0) accNum = AccountInfoInteger(ACCOUNT_LOGIN);
   
   // Generate key
   string key = GenerateLicenseKey(accNum);
   
   // Show on panel
   ShowAdminPanel(accNum, key);
   
   // Print in Experts tab
   Print("╔══════════════════════════════════════════╗");
   Print("║     ANTU TRADING - KEY GENERATOR        ║");
   Print("╠══════════════════════════════════════════╣");
   Print("║  Account : ", accNum);
   Print("║  Key     : ", key);
   Print("║  Password: ANTU2024PRO");
   Print("╠══════════════════════════════════════════╣");
   Print("║  Client ko yeh 2 cheezein do:           ║");
   Print("║  1. Password: ANTU2024PRO               ║");
   Print("║  2. License Key: ", key);
   Print("╚══════════════════════════════════════════╝");
   
   // Alert popup
   Alert("Account: " + IntegerToString(accNum) + 
         "\nLicense Key: " + key +
         "\nPassword: ANTU2024PRO" +
         "\n\nClient ko yeh do!");
   
   // Chart comment bhi
   Comment("\n"
          +"  ══════════════════════════════════════\n"
          +"  ANTU TRADING - LICENSE KEY GENERATOR\n"
          +"  ══════════════════════════════════════\n"
          +"  Account : "+IntegerToString(accNum)+"\n"
          +"  Key     : "+key+"\n"
          +"  Password: ANTU2024PRO\n"
          +"  ══════════════════════════════════════\n"
          +"  Client ko do:\n"
          +"  1. Password: ANTU2024PRO\n"
          +"  2. License Key: "+key+"\n"
          +"  ══════════════════════════════════════\n");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
   Comment("");
   ObjectsDeleteAll(0,"ADM_");
}

//+------------------------------------------------------------------+
//| OnTick - No trading, just panel                                  |
//+------------------------------------------------------------------+
void OnTick(){
   // Owner panel does nothing on tick - just shows key
}
//+------------------------------------------------------------------+
