# -*- coding: utf-8 -*-
"""
play.py - Interactive CLI runner for the flesh-pit text game simulator.
Faithfully executes the exact game logic, formulas, and menus defined in the ERB scripts
and aligns with the original Godot 4.7 flesh-pit architecture.

Supports instant Korean / English toggle anytime via 'l' or 'lang'!
"""

import sys
import random

# Configure Unicode console I/O
for stream in (sys.stdout, sys.stderr, sys.stdin):
    if hasattr(stream, 'encoding') and stream.encoding and stream.encoding.lower() != 'utf-8':
        try:
            stream.reconfigure(encoding='utf-8', errors='replace')
        except Exception:
            pass

# World Constants
SEG_COUNT = 60
CORE_SEGS = 18    # 0 ~ 9m (Segments 0..17)
MANTLE_SEGS = 36  # 9 ~ 18m (Segments 18..35)
SURFACE_SEGS = 54 # 18 ~ 27m (Segments 36..53)

# Tissues
TISSUE_COMPRESSIVE = 0
TISSUE_CONTRACTILE = 1
TISSUE_NERVE = 2
TISSUE_MEMBRANE = 3
TISSUE_DISSOLVED = 4

TISSUE_NAMES_KO = {
    TISSUE_COMPRESSIVE: "압축 조직 (물렁함)",
    TISSUE_CONTRACTILE: "수축 조직 (주기 수축)",
    TISSUE_NERVE: "신경 조직 (전기 충전)",
    TISSUE_MEMBRANE: "질긴 막 (칼 필요)",
    TISSUE_DISSOLVED: "영구 용해된 살 (섭취 불가)",
}

TISSUE_NAMES_EN = {
    TISSUE_COMPRESSIVE: "Compressive Tissue (Soft)",
    TISSUE_CONTRACTILE: "Contractile Tissue (Periodic Contraction)",
    TISSUE_NERVE: "Nerve Tissue (Electric Charge)",
    TISSUE_MEMBRANE: "Tough Membrane (Requires Knife)",
    TISSUE_DISSOLVED: "Dissolved Flesh (Inedible)",
}

ITEM_NAMES_KO = {
    "knife": "날카로운 칼",
    "blender": "주방용 믹서기",
    "big_saw": "대형 공업용 톱",
    "barrier": "확장 방벽",
    "spray_cheap": "표면 용해 스프레이",
    "spray_deep": "심층 용해 스프레이",
    "canary_feed": "카나리아 먹이",
    "tumor_bag": "종양 보관 가방",
    "junk": "고철 잡동사니"
}

ITEM_NAMES_EN = {
    "knife": "Sharp Knife",
    "blender": "Kitchen Blender",
    "big_saw": "Industrial Saw",
    "barrier": "Spreader Barrier",
    "spray_cheap": "Surface Dissolve Spray",
    "spray_deep": "Deep Dissolve Spray",
    "canary_feed": "Canary Feed",
    "tumor_bag": "Tumor Bag",
    "junk": "Scrap Metal"
}


class GameState:
    def __init__(self):
        # Language: 'ko' or 'en'
        self.lang = 'ko'

        # World Arrays (0 to SEG_COUNT-1)
        self.seg_density = [850] * SEG_COUNT
        self.seg_tissue = [TISSUE_COMPRESSIVE] * SEG_COUNT
        self.seg_barrier_hp = [0] * SEG_COUNT
        self.seg_tumor = [0] * SEG_COUNT
        
        # Player state
        self.player_pos_seg = 0
        self.game_seconds = 0
        self.player_hp = 100
        self.stomach_fill = 0      # 1/100 scale: 10000 = 100.0 units
        self.flesh_in_hand = 0
        self.crush_ms = 0
        self.is_crouching = False
        self.last_checked_clear = -1
        
        # Currency & Progression
        self.teeth_in_tank = 0
        self.teeth_in_hand = 0
        self.hair_common = 0
        self.hair_core = 0
        self.hair_mantle = 0
        self.hair_surface = 0
        self.carry_common = 0
        self.carry_core = 0
        self.carry_mantle = 0
        self.carry_surface = 0
        self.tumor_points = 0
        self.tumors_eaten = 0
        
        # Inventory
        self.equipped_right = ""
        self.equipped_left = ""
        self.own_knife = False
        self.own_blender = False
        self.blender_charge = 0
        self.own_big_saw = False
        self.item_barriers = 0
        self.item_spray_cheap = 0
        self.item_spray_deep = 0
        self.item_canary_feed = 0
        self.has_tumor_bag = False
        self.has_belt = False
        self.has_canary = False
        self.canary_feed_timer = 0
        self.carried_tumors = []
        
        # Restroom
        self.tank_lid_open = False
        self.bowl_flesh = 0
        self.vent_is_open = False
        self.vent_teeth_placed = 0
        self.vent_offers = []
        self.first_flush_done = False
        self.hands_bloody = False
        
        # Mutations
        self.mut_m = [False] * 31
        self.mut_t = [False] * 8
        
        self.init_world()

    def toggle_lang(self):
        if self.lang == 'ko':
            self.lang = 'en'
            print("\n[Language changed to English]")
        else:
            self.lang = 'ko'
            print("\n[언어가 한국어로 변경되었습니다]")
        
    def init_world(self):
        for i in range(SEG_COUNT):
            self.seg_density[i] = 850
            if i < CORE_SEGS:
                self.seg_tissue[i] = TISSUE_COMPRESSIVE
            elif i < MANTLE_SEGS:
                self.seg_tissue[i] = TISSUE_CONTRACTILE
            elif i < SURFACE_SEGS:
                self.seg_tissue[i] = TISSUE_NERVE
            else:
                self.seg_tissue[i] = TISSUE_MEMBRANE
                
            # Shell boundary membranes
            if i in (CORE_SEGS - 1, MANTLE_SEGS - 1):
                self.seg_tissue[i] = TISSUE_MEMBRANE
                self.seg_density[i] = 1000
                
        # Restroom doorway threshold (segment 0) is open doorway column
        self.seg_density[0] = 0
        
        # Tumors embedded in flesh
        self.seg_tumor[5] = 1   # 핵 기형종
        self.seg_tumor[12] = 2  # 핵 물혹
        self.seg_tumor[25] = 3  # 맨틀 똬리 근종
        self.seg_tumor[32] = 4  # 맨틀 쌍둥이 주머니
        self.seg_tumor[42] = 5  # 지표면 별 신경종
        self.seg_tumor[50] = 6  # 지표면 귀 덩어리

    def get_stomach_capacity(self):
        cap = 10000
        if self.mut_m[1]: cap += 2000
        if self.mut_t[4]: cap *= 2
        return cap

    def get_overfill_capacity(self):
        ocap = 6000
        if self.mut_m[30]: ocap += 4000
        return ocap

    def get_overfill_chew_mult(self):
        cap = self.get_stomach_capacity()
        if self.stomach_fill <= cap:
            return 100
        overfill = self.stomach_fill - cap
        max_mult = 240 if self.mut_m[2] else 300
        return 100 + int((max_mult - 100) * overfill / self.get_overfill_capacity())

    def calc_chew_duration_ms(self, target_seg):
        tissue = self.seg_tissue[target_seg]
        base_ms = 450
        hardness = 100
        
        if tissue == TISSUE_COMPRESSIVE:
            hardness = 70 if self.mut_m[8] else 100
        elif tissue == TISSUE_CONTRACTILE:
            hardness = 60 if self.mut_m[18] else 130
        elif tissue == TISSUE_NERVE:
            hardness = 150
        elif tissue == TISSUE_MEMBRANE:
            hardness = 200
            
        tool_mult = 100
        if self.equipped_right == "knife":
            tool_mult = 80
            
        if self.mut_m[4]:
            tool_mult = tool_mult * 85 // 100
            
        if self.mut_t[3]:
            tool_mult = tool_mult * 40 // 100
            
        over_mult = self.get_overfill_chew_mult()
        return int(base_ms * (hardness / 100.0) * (tool_mult / 100.0) * (over_mult / 100.0))

    def apply_world_regen(self, elapsed_ms):
        self.game_seconds += elapsed_ms // 1000
        for i in range(SEG_COUNT):
            if i == 0:
                continue
                
            tissue = self.seg_tissue[i]
            if tissue in (TISSUE_DISSOLVED, TISSUE_MEMBRANE):
                continue
                
            # Barrier protection
            if self.seg_barrier_hp[i] > 0:
                pressure = (1000 - self.seg_density[i]) * (i + 10) // 20
                self.seg_barrier_hp[i] -= pressure * elapsed_ms // 1000
                if self.seg_barrier_hp[i] <= 0:
                    self.seg_barrier_hp[i] = 0
                    if i == self.player_pos_seg:
                        if self.lang == 'en':
                            print("\n[WARNING] Overburdened spreader barrier snapped and shattered!")
                        else:
                            print("\n[경고] 버티지 못한 방벽이 '뽀잉' 하고 튕겨 나가며 산산조각 났다!")
                continue
                
            # Body protection radius
            if i == self.player_pos_seg and tissue != TISSUE_CONTRACTILE:
                if self.mut_t[7]:
                    continue
                if self.seg_density[i] >= 400:
                    continue
                    
            mult = 150 if tissue == TISSUE_COMPRESSIVE else (100 if tissue == TISSUE_CONTRACTILE else 80)
            if (i > 0 and self.seg_tissue[i-1] == TISSUE_DISSOLVED) or (i < SEG_COUNT - 1 and self.seg_tissue[i+1] == TISSUE_DISSOLVED):
                mult *= 2
                
            regen_amt = (3 * mult * elapsed_ms) // 100000
            if regen_amt < 1 and elapsed_ms >= 200:
                regen_amt = 1
            self.seg_density[i] = min(850, self.seg_density[i] + regen_amt)
            
            # Periodic mantle contraction wave
            if tissue == TISSUE_CONTRACTILE and (self.game_seconds % 8) < 3 and self.seg_density[i] < 800:
                self.seg_density[i] = min(850, self.seg_density[i] + 20)

    def calc_pressure_and_crush(self, elapsed_ms):
        min_clear = min(1000 - self.seg_density[k] for k in range(self.player_pos_seg + 1))
        squeeze = self.seg_density[self.player_pos_seg]
        if self.mut_m[5]: squeeze = int(squeeze * 0.85)
        if self.mut_t[4]: squeeze = int(squeeze * 1.30)
        
        max_crush = 9000 if self.mut_m[6] else 6000
        if squeeze >= 800:
            self.crush_ms += elapsed_ms
            pct = min(100, self.crush_ms * 100 // max_crush)
            if self.lang == 'en':
                print(f"\n[DANGER!] Regenerated flesh is crushing your ribs! [Crush Progress: {pct}%]")
            else:
                print(f"\n[위험!] 재생된 살점이 온몸을 으스러뜨리며 조여온다! [압사 진행: {pct}%]")
            if self.crush_ms >= max_crush:
                self.on_death()
                return squeeze, min_clear, True
        else:
            if self.crush_ms > 0:
                self.crush_ms = max(0, self.crush_ms - elapsed_ms * 2)
        return squeeze, min_clear, False

    def on_death(self):
        if self.lang == 'en':
            print("\n================================================================================")
            print(" [DEATH] Crushed by solid encroaching flesh...")
            print(" You awake next to the toilet, breathless, having lost your carried flesh and items.")
            print("================================================================================\n")
        else:
            print("\n================================================================================")
            print(" [사망] 사방에서 밀려든 고체 살점에 압사했습니다...")
            print(" 위장의 살점과 소지품을 잃고 화장실 변기 옆에서 거친 숨을 내쉬며 깨어납니다.")
            print("================================================================================\n")
        self.stomach_fill = 0
        self.flesh_in_hand = 0
        self.item_barriers = 0
        self.item_spray_cheap = 0
        self.item_spray_deep = 0
        self.teeth_in_hand = 0
        self.player_pos_seg = 0
        self.crush_ms = 0
        self.has_canary = False
        self.last_checked_clear = -1


def ask_prompt(game, prompt_ko="선택> [L:언어전환] ", prompt_en="Select> [L:Lang] "):
    prompt = prompt_en if game.lang == 'en' else prompt_ko
    try:
        val = input(prompt).strip()
    except EOFError:
        return ""
    if val.lower() in ("l", "lang", "language", "한영"):
        game.toggle_lang()
        return "LANG_TOGGLED"
    return val


def run_toilet_menu(game):
    while True:
        print("\n" + "-" * 50)
        if game.lang == 'en':
            print(" [Toilet] Clean white porcelain toilet.")
            print(f" In bowl: {game.bowl_flesh // 100} units vomited flesh")
            print(f" In stomach: {game.stomach_fill // 100} units flesh")
            print("-" * 50)
            print("[1] Vomit flesh from stomach into bowl")
            print("[2] Press flush lever")
            print("[0] Back")
        else:
            print(" [변기 앞] 깨끗한 도자기 변기다.")
            print(f" 변기 안: {game.bowl_flesh // 100}단위 게워낸 살점")
            print(f" 위장 안: {game.stomach_fill // 100}단위 살점")
            print("-" * 50)
            print("[1] 위장의 살점 게워내기")
            print("[2] 변기 레버를 눌러 물 내리기")
            print("[0] 돌아가기")

        sub = ask_prompt(game)
        if sub == "LANG_TOGGLED":
            continue
        if not sub or sub == "0":
            break

        if sub == "1":
            if game.stomach_fill > 0:
                game.bowl_flesh += game.stomach_fill
                amt = game.stomach_fill // 100
                game.stomach_fill = 0
                if game.lang == 'en':
                    print(f">> Blegh! Vomited {amt} units of stomach flesh into the toilet.")
                else:
                    print(f">> 욱-! 위장의 살점 {amt}단위를 변기에 게워냈습니다.")
            else:
                print(">> " + ("Nothing in stomach to vomit." if game.lang == 'en' else "게워낼 살점이 없습니다."))
        elif sub == "2":
            if game.bowl_flesh > 0:
                teeth_gain = max(1, (game.bowl_flesh * 8) // 10000)
                game.teeth_in_tank += teeth_gain
                game.bowl_flesh = 0
                if game.lang == 'en':
                    print(f">> Whoosh! Clear water gulps down the flesh; {teeth_gain} teeth rattle into the tank!")
                    print("   (Note: Toilet flushing awards teeth to tank, hair is not granted)")
                else:
                    print(f">> 쏴아아-! 시원한 물살이 살점을 삼키고 물탱크에 이빨 {teeth_gain}개가 달그락거리며 차올랐습니다!")
                    print("   (주의: 변기 물내림 시 털은 지급되지 않으며 이빨만 적립됩니다)")
                if not game.first_flush_done:
                    game.first_flush_done = True
                    if game.lang == 'en':
                        print("\nFrom the ceiling vent: '......Huh? Hey! I heard that! Someone's in there, right?!'")
                    else:
                        print("\n천장 환풍구 너머: '......어? 어어? 나 똑똑히 들었다? 거기 누구 있어? 있지?!'")
            else:
                if game.lang == 'en':
                    print(">> The flush echoes cleanly with water only. No teeth deposited.")
                else:
                    print(">> 쏴아아- 맑은 물만 내려갑니다. 살점이 없어 이빨이 생기지 않았습니다.")


def run_tank_menu(game):
    while True:
        print("\n" + "-" * 50)
        if game.lang == 'en':
            print(" [Water Tank] Ceramic tank behind the toilet bowl.")
            print(f" Tank: {'Lid is OPEN' if game.tank_lid_open else 'Lid is closed tightly'}")
            print(f" Teeth inside tank: {game.teeth_in_tank} | Teeth in hand: {game.teeth_in_hand}")
            print("-" * 50)
            if not game.tank_lid_open:
                print("[1] Open heavy tank lid")
            else:
                print("[1] Scoop teeth with bare hand (Max 4)")
                print("[2] Put held teeth back into tank")
                print("[3] Close lid")
            print("[0] Back")
        else:
            print(" [물탱크 앞] 변기 뒤편의 도자기 물탱크다.")
            print(f" 물탱크: {'뚜껑이 열려 있음' if game.tank_lid_open else '뚜껑이 닫혀 있음'}")
            print(f" 물탱크 속 이빨: {game.teeth_in_tank}개 | 손에 쥔 이빨: {game.teeth_in_hand}개")
            print("-" * 50)
            if not game.tank_lid_open:
                print("[1] 무거운 물탱크 뚜껑 열기")
            else:
                print("[1] 맨손으로 이빨 집어 올리기 (최대 4개)")
                print("[2] 손에 쥔 이빨 도로 넣기")
                print("[3] 뚜껑 닫기")
            print("[0] 돌아가기")

        sub = ask_prompt(game)
        if sub == "LANG_TOGGLED":
            continue
        if not sub or sub == "0":
            break

        if sub == "1" and not game.tank_lid_open:
            game.tank_lid_open = True
            print(">> " + ("Clack! Opened the heavy ceramic tank lid." if game.lang == 'en' else "달칵, 무거운 도자기 물탱크 뚜껑을 열었습니다."))
        elif sub == "1" and game.tank_lid_open:
            scoop = min(4, game.teeth_in_tank)
            if scoop > 0:
                game.teeth_in_tank -= scoop
                game.teeth_in_hand += scoop
                print(">> " + (f"Scooped {scoop} cold teeth into your hand." if game.lang == 'en' else f"차가운 이빨 {scoop}개를 손에 쥐었습니다."))
            else:
                print(">> " + ("No teeth left in the tank." if game.lang == 'en' else "물탱크에 더 이상 이빨이 없습니다."))
        elif sub == "2" and game.tank_lid_open:
            if game.teeth_in_hand > 0:
                game.teeth_in_tank += game.teeth_in_hand
                held = game.teeth_in_hand
                game.teeth_in_hand = 0
                print(">> " + (f"Returned {held} teeth back into the tank." if game.lang == 'en' else f"손에 쥔 이빨 {held}개를 물탱크에 도로 넣었습니다."))
            else:
                print(">> " + ("No teeth in your hand." if game.lang == 'en' else "손에 쥔 이빨이 없습니다."))
        elif sub == "3" and game.tank_lid_open:
            game.tank_lid_open = False
            print(">> " + ("Carefully closed the tank lid." if game.lang == 'en' else "물탱크 뚜껑을 조심스럽게 닫았습니다."))


def run_mirror_menu(game):
    while True:
        print("\n" + "-" * 50)
        if game.lang == 'en':
            print(" [Sink & Mirror]")
            print(f" Hair Owned: Common {game.hair_common} | Core(Pink) {game.hair_core} | Mantle(Purple) {game.hair_mantle} | Surface(Yellow) {game.hair_surface}")
            if game.tumor_points > 0:
                print(f" Belly Bumps: {game.tumor_points} throbbing under skin")
            print("-" * 50)
            print("[1] Wash hands under running tap")
            print("[2] Look into full mirror (Mutation screen)")
            if game.tumor_points > 0:
                print("[3] Squeeze and burst belly tumor bump")
            print("[0] Back")
        else:
            print(" [세면대와 거울 앞]")
            print(f" 보유 털: 공통 {game.hair_common}가닥 | 핵(분홍) {game.hair_core}가닥 | 맨틀(보라) {game.hair_mantle}가닥 | 지표면(노랑) {game.hair_surface}가닥")
            if game.tumor_points > 0:
                print(f" 배의 혹: {game.tumor_points}개 꿈틀거리고 있음")
            print("-" * 50)
            print("[1] 손 씻기")
            print("[2] 전신 거울 보기")
            if game.tumor_points > 0:
                print("[3] 배의 종양 혹 터뜨리기")
            print("[0] 돌아가기")

        sub = ask_prompt(game)
        if sub == "LANG_TOGGLED":
            continue
        if not sub or sub == "0":
            break

        if sub == "1":
            game.hands_bloody = False
            print(">> " + ("Splaaash- Cleansed all blood from your hands with cold tap water." if game.lang == 'en' else "솨아아- 차가운 물로 양손의 피를 깨끗이 씻어냈습니다."))
        elif sub == "2":
            run_mutation_shop(game)
        elif sub == "3" and game.tumor_points > 0:
            burst_tumor(game)


def run_mutation_shop(game):
    while True:
        print("\n" + "=" * 65)
        if game.lang == 'en':
            print("                [ BODY MUTATION SCREEN ]")
            print(f" Resources: Common {game.hair_common} | Core {game.hair_core} | Mantle {game.hair_mantle} | Surface {game.hair_surface}")
            print("=" * 65)
            print(f" [1] M01 Expanded Stomach (Capacity +20) [12 Common] - {'OWNED' if game.mut_m[1] else 'AVAILABLE'}")
            print(f" [2] M02 Wide Throat (Overfill Chew Penalty Reduced) [12 Common] - {'OWNED' if game.mut_m[2] else 'AVAILABLE'}")
            print(f" [4] M04 Jutting Jaw (Base Chew x0.85) [12 Common] - {'OWNED' if game.mut_m[4] else 'AVAILABLE'}")
            print(f" [5] M05 Folding Shoulders (Squeeze x0.85) [12 Common] - {'OWNED' if game.mut_m[5] else 'AVAILABLE'}")
            print(f" [6] M06 Long Breath (Crush Limit +3s) [12 Common] - {'OWNED' if game.mut_m[6] else 'AVAILABLE'}")
            print(f" [7] M07 Broad Palm (+1 Cell Torn per Action) [5 Core] - {'OWNED' if game.mut_m[7] else 'AVAILABLE'}")
            print(f" [8] M08 Webbed Fingers (Compressive Chew x0.7) [5 Core] - {'OWNED' if game.mut_m[8] else 'AVAILABLE'}")
            print(f" [9] M09 Thick Nails (Tear Membrane Barehanded) [5 Core] - {'OWNED' if game.mut_m[9] else 'AVAILABLE'}")
            print(f"[10] M10 Long Knuckles (Reach +0.4m) [5 Core] - {'OWNED' if game.mut_m[10] else 'AVAILABLE'}")
            print(f"[18] M18 Mole Paws (Contractile Chew x0.6) [10 Mantle] - {'OWNED' if game.mut_m[18] else 'AVAILABLE'}")
            print(f"[19] M19 Peristaltic Crawl (Accelerate in Tight Squeeze x1.3) [10 Mantle] - {'OWNED' if game.mut_m[19] else 'AVAILABLE'}")
            print(f"[20] M20 Hyperflexible Joints (Ignore Squeeze Slowdown) [10 Mantle] - {'OWNED' if game.mut_m[20] else 'AVAILABLE'}")
            print(f"[29] M29 Dormancy (Resurrect in Restroom after Crush) [15 Mantle] - {'OWNED' if game.mut_m[29] else 'AVAILABLE'}")
            print(f"[30] M30 Neck Pouch (Overfill Capacity +40) [15 Core] - {'OWNED' if game.mut_m[30] else 'AVAILABLE'}")
            print("[0] Close")
        else:
            print("                [ 신 체  변 이  화 면 ]")
            print(f" 자원: 공통 털 {game.hair_common} | 핵 털 {game.hair_core} | 맨틀 털 {game.hair_mantle} | 지표 털 {game.hair_surface}")
            print("=" * 65)
            print(f" [1] M01 늘어난 위 (위장 용량 +20) [공통 12가닥] - {'습득 완료' if game.mut_m[1] else '미습득'}")
            print(f" [2] M02 넓은 목구멍 (과식 씹기 배율 완화) [공통 12가닥] - {'습득 완료' if game.mut_m[2] else '미습득'}")
            print(f" [4] M04 불거진 턱 (기본 씹기 x0.85) [공통 12가닥] - {'습득 완료' if game.mut_m[4] else '미습득'}")
            print(f" [5] M05 접히는 어깨 (압박률 경감 x0.85) [공통 12가닥] - {'습득 완료' if game.mut_m[5] else '미습득'}")
            print(f" [6] M06 긴 숨 (압사 시간 +3초) [공통 12가닥] - {'습득 완료' if game.mut_m[6] else '미습득'}")
            print(f" [7] M07 넓은 손바닥 (한 번에 뜯는 셀 +1) [핵 5가닥] - {'습득 완료' if game.mut_m[7] else '미습득'}")
            print(f" [8] M08 물갈퀴 (압축 살점 씹기 x0.7) [핵 5가닥] - {'습득 완료' if game.mut_m[8] else '미습득'}")
            print(f" [9] M09 두꺼운 손톱 (맨손 막 뜯기) [핵 5가닥] - {'습득 완료' if game.mut_m[9] else '미습득'}")
            print(f"[10] M10 긴 마디 (도달 거리 +0.4m) [핵 5가닥] - {'습득 완료' if game.mut_m[10] else '미습득'}")
            print(f"[18] M18 두더지 앞발 (수축 살점 씹기 x0.6) [맨틀 10가닥] - {'습득 완료' if game.mut_m[18] else '미습득'}")
            print(f"[19] M19 연동 기기 (협착 시 가속 x1.3) [맨틀 10가닥] - {'습득 완료' if game.mut_m[19] else '미습득'}")
            print(f"[20] M20 과유연 관절 (협착 감속 무시) [맨틀 10가닥] - {'습득 완료' if game.mut_m[20] else '미습득'}")
            print(f"[29] M29 휴면 (압사 시 30초 뒤 화장실 부활) [맨틀 15가닥] - {'습득 완료' if game.mut_m[29] else '미습득'}")
            print(f"[30] M30 목주머니 (과식 한도 +40) [핵 15가닥] - {'습득 완료' if game.mut_m[30] else '미습득'}")
            print("[0] 닫기")

        msub = ask_prompt(game)
        if msub == "LANG_TOGGLED":
            continue
        if not msub or msub == "0":
            break

        try:
            idx = int(msub)
        except ValueError:
            continue
            
        cost_pool = {
            1: (12, "common"), 2: (12, "common"), 4: (12, "common"), 5: (12, "common"), 6: (12, "common"),
            7: (5, "core"), 8: (5, "core"), 9: (5, "core"), 10: (5, "core"),
            18: (10, "mantle"), 19: (10, "mantle"), 20: (10, "mantle"), 29: (15, "mantle"), 30: (15, "core")
        }
        if idx not in cost_pool:
            print(">> " + ("Invalid mutation number." if game.lang == 'en' else "올바른 변이 번호가 아닙니다."))
            continue
        if game.mut_m[idx]:
            print(">> " + ("Mutation already acquired." if game.lang == 'en' else "이미 습득한 변이입니다."))
            continue
        cost, pool = cost_pool[idx]
        cur = getattr(game, f"hair_{pool}")
        if cur < cost:
            print(">> " + (f"Not enough {pool} hair! (Have: {cur} / Need: {cost})" if game.lang == 'en' else f"{pool} 털이 부족합니다! (보유: {cur} / 필요: {cost})"))
            continue
        setattr(game, f"hair_{pool}", cur - cost)
        game.mut_m[idx] = True
        print("\n>> " + (f"Snap-! Hair sheds as Mutation M{idx:02d} permanently manifests on your flesh!" if game.lang == 'en' else f"쩌적-! 털이 빠져나가며 변이 M{idx:02d}가 영구 발현되었습니다!"))


def burst_tumor(game):
    if game.tumor_points <= 0:
        return
    cands = [i for i in range(1, 8) if not game.mut_t[i]]
    if not cands:
        print(">> " + ("All tumor mutations have already manifested." if game.lang == 'en' else "이미 모든 종양 변이가 발현되었습니다."))
        game.tumor_points = 0
        return
    pick = random.choice(cands)
    game.tumor_points -= 1
    game.mut_t[pick] = True
    names_ko = {
        1: "T1 반향정위 (통로 상태 감지)",
        2: "T2 세 번째 팔 (믹서기 항상 휴대)",
        3: "T3 손바닥 입 (씹기 시간 대폭 단축 x0.4)",
        4: "T4 부푼 몸통 (위장 용량 2배, 통로 압박 증가)",
        5: "T5 어안 (넓은 시야)",
        6: "T6 세로 턱 (칼 없이 맨손 막 찢기)",
        7: "T7 부채 갈비 (정지 시 주변 1.5m 재생 정지)"
    }
    names_en = {
        1: "T1 Echolocation (Senses passage clearance)",
        2: "T2 Third Arm (Always carry blender)",
        3: "T3 Palm Mouth (Chewing time drastically shortened x0.4)",
        4: "T4 Swollen Torso (Stomach cap x2, higher squeeze penalty)",
        5: "T5 Fish Eyes (Wide peripheral vision)",
        6: "T6 Vertical Jaw (Tear tough membrane barehanded)",
        7: "T7 Fan Ribs (Halts 1.5m flesh regen while standing still)"
    }
    if game.lang == 'en':
        print(f"\n>> Squish-! You forcefully squeeze and pop the belly tumor bump!")
        print(f"   Blackish-red bile floods inward. Acquired Tumor Mutation [{names_en[pick]}]!")
    else:
        print(f"\n>> 뿌직-! 배에 솟아오른 종양 혹을 손가락으로 으깨어 터뜨렸습니다!")
        print(f"   검붉은 체액이 스며들며 강력한 종양 변이 [{names_ko[pick]}] 발현!")


def run_vent_menu(game):
    while True:
        print("\n" + "-" * 50)
        if game.lang == 'en':
            print(" [Exhaust Vent]")
        else:
            print(" [환풍구 앞]")

        if not game.vent_is_open:
            if game.lang == 'en':
                print(" The metal vent grates are closed.")
                print("[1] Open metal vent grates")
                print("[0] Back")
            else:
                print(" 환풍구 쇠창살이 닫혀 있습니다.")
                print("[1] 환풍구 쇠창살 열기")
                print("[0] 돌아가기")

            sub = ask_prompt(game)
            if sub == "LANG_TOGGLED":
                continue
            if not sub or sub == "0":
                break

            if sub == "1":
                game.vent_is_open = True
                if game.lang == 'en':
                    print(">> Creak- As the grates open, two glittering eyes glare down from the dark!")
                    if not game.first_flush_done:
                        print("Voice from vent: '......What're you lookin' at?! How long was this open!'")
                    else:
                        if game.teeth_in_hand > 0:
                            print("Voice from vent: 'Here it is, here it comes! Show me the sticks! In your hand!'")
                        else:
                            print("Voice from vent: 'Nothing? Why open it then. Go get some. Hurry.'")
                else:
                    print(">> 끼이익- 쇠창살을 열자 어둠 속에서 두 개의 번뜩이는 눈동자가 번뜩였습니다!")
                    if not game.first_flush_done:
                        print("환풍구 너머: '......뭘 봐?! 언제부터 열려 있었어!'")
                    else:
                        if game.teeth_in_hand > 0:
                            print("환풍구 너머: '왔다 왔다 왔다. 봉 보여줘! 손에 쥔 거!'")
                        else:
                            print("환풍구 너머: '없어? 없으면 왜 열어. 가서 가져와. 빨리.'")
        else:
            if game.lang == 'en':
                print(f" Teeth on vent ledge: {game.vent_teeth_placed} | Teeth in hand: {game.teeth_in_hand}")
                if game.vent_offers:
                    print(" Goods extended from the darkness:")
                    for idx, off in enumerate(game.vent_offers, 1):
                        name = ITEM_NAMES_EN.get(off, off)
                        print(f" [{idx}] Pick up {name}")
                print("[4] Place held teeth onto vent ledge")
                print("[5] Offer something else")
                print("[6] Close vent grates")
                print("[0] Back")
            else:
                print(f" 환풍구에 올린 이빨: {game.vent_teeth_placed}개 | 손에 쥔 이빨: {game.teeth_in_hand}개")
                if game.vent_offers:
                    print(" 어둠 속에서 내민 물품:")
                    for idx, off in enumerate(game.vent_offers, 1):
                        name = ITEM_NAMES_KO.get(off, off)
                        print(f" [{idx}] {name} 집어 들기")
                print("[4] 손에 쥔 이빨을 환풍구에 올리기")
                print("[5] 다른 물건 내밀기")
                print("[6] 환풍구 닫기")
                print("[0] 돌아가기")

            sub = ask_prompt(game)
            if sub == "LANG_TOGGLED":
                continue
            if not sub or sub == "0":
                break

            if sub in ("1", "2", "3") and len(game.vent_offers) >= int(sub):
                picked_id = game.vent_offers[int(sub) - 1]
                name_disp = ITEM_NAMES_EN.get(picked_id, picked_id) if game.lang == 'en' else ITEM_NAMES_KO.get(picked_id, picked_id)
                if game.lang == 'en':
                    print(f">> Reached out and took the {name_disp}!")
                    print("   Hands in the darkness snatch all teeth and remaining items away.")
                else:
                    print(f">> 손을 뻗어 {name_disp}을(를) 집어 들었습니다!")
                    print("   어둠 속의 손이 남은 물건들과 이빨을 낚아채 어둠 속으로 끌고 들어갔습니다.")

                if picked_id == "knife":
                    game.own_knife = True
                    game.equipped_right = "knife"
                elif picked_id == "barrier":
                    game.item_barriers = min(3, game.item_barriers + 1)
                elif picked_id == "canary_feed":
                    game.item_canary_feed = min(3, game.item_canary_feed + 1)
                elif picked_id == "spray_cheap":
                    game.item_spray_cheap += 6
                elif picked_id == "big_saw":
                    game.own_big_saw = True
                    game.equipped_right = "big_saw"
                elif picked_id == "tumor_bag":
                    game.has_tumor_bag = True
                game.vent_offers = []
                game.vent_teeth_placed = 0

            elif sub == "4":
                if game.teeth_in_hand > 0:
                    game.vent_teeth_placed += game.teeth_in_hand
                    game.teeth_in_hand = 0
                    if game.lang == 'en':
                        print(f">> Placed teeth onto the vent shelf. (Total {game.vent_teeth_placed})")
                        if not game.has_belt:
                            game.has_belt = True
                            print("From vent: 'Nice! Since you brought sticks, take this as a bonus.' (Obtained Work Belt)")
                        if game.vent_teeth_placed < 4:
                            game.vent_offers = ["junk"]
                            print("From vent: '......This? For this? Hmph, I only got junk.'")
                        elif game.vent_teeth_placed < 12:
                            game.vent_offers = ["knife", "canary_feed", "spray_cheap"]
                            print("From vent: 'Good. Fair enough. Pick.'")
                        else:
                            game.vent_offers = ["big_saw", "tumor_bag", "canary_feed"]
                            print("From vent: 'Whoa! This much?! Saved this for later. Pick!'")
                    else:
                        print(f">> 환풍구 선반에 이빨을 올렸습니다. (총 {game.vent_teeth_placed}개)")
                        if not game.has_belt:
                            game.has_belt = True
                            print("환풍구 너머: '좋아! 봉을 줬으니 이건 덤이다.' (작업 벨트 획득)")
                        if game.vent_teeth_placed < 4:
                            game.vent_offers = ["junk"]
                            print("환풍구 너머: '......이거? 이걸로? 이런 거밖에 없어.'")
                        elif game.vent_teeth_placed < 12:
                            game.vent_offers = ["knife", "canary_feed", "spray_cheap"]
                            print("환풍구 너머: '좋아. 공평해. 골라.'")
                        else:
                            game.vent_offers = ["big_saw", "tumor_bag", "canary_feed"]
                            print("환풍구 너머: '어어! 이렇게나? 아껴둔 거다. 골라!'")
                else:
                    print(">> " + ("No teeth in hand! Scoop some from the tank first." if game.lang == 'en' else "손에 쥔 이빨이 없습니다! 물탱크에서 꺼내와야 합니다."))

            elif sub == "5":
                if game.has_canary:
                    print(">> " + ("Offered canary: '......Cute. Take it back. Can't keep birds here.'" if game.lang == 'en' else "카나리아를 내밀자: '......귀엽네. 가져가. 나 새 못 키워.'"))
                elif game.hands_bloody:
                    print(">> " + ("Offered bloody hands: 'Keep your hands out. This is my room.'" if game.lang == 'en' else "피 묻은 손을 들이밀자: '손 넣지 마. 여긴 내 방이야.'"))
                else:
                    print(">> " + ("Empty hand: 'No bird, nothing. Just an empty hand. What are you showing me.'" if game.lang == 'en' else "새가 없습니다: '새가 없잖아. 빈손이네. 뭘 들이미는 거야.'"))

            elif sub == "6":
                game.vent_is_open = False
                print(">> " + ("Clacked the metal vent grates shut." if game.lang == 'en' else "쇠창살을 탁 소리 나게 닫았습니다."))


def run_tunnel_expedition(game):
    while True:
        pos = game.player_pos_seg
        target_seg = pos + 1
        
        sq, min_clear, dead = game.calc_pressure_and_crush(0)
        if dead:
            return "restroom"
            
        if game.lang == 'en':
            shell_name = "Core" if pos < CORE_SEGS else ("Mantle" if pos < MANTLE_SEGS else "Surface")
            t_name = TISSUE_NAMES_EN.get(game.seg_tissue[pos], "Flesh")
            print("\n" + "=" * 80)
            print(f"[Location] Depth {pos * 0.5:.1f}m ({shell_name} - {t_name}) | Time: {game.game_seconds // 60:02d}:{game.game_seconds % 60:02d}")
            print(f"[Status] Stomach: {game.stomach_fill // 100}/{game.get_stomach_capacity() // 100} units | HP: {game.player_hp}/100 | Weapon: {ITEM_NAMES_EN.get(game.equipped_right, 'Bare Hands')}")
            
            front_d = game.seg_density[target_seg] // 10 if target_seg < SEG_COUNT else 0
            print(f"[Passage] Front Wall Density: {front_d}% | Squeeze: {'DANGER (Slowdown)' if sq >= 500 else 'Clear'}")
            
            if game.has_canary:
                fed_early = game.canary_feed_timer > 0
                feed_tag = " (Fed: High Alert)" if fed_early else ""
                warn_threshold = 350 if fed_early else 200
                caution_threshold = 650 if fed_early else 500
                if min_clear < warn_threshold:
                    print(f"[Canary] Screams and flutters violently at your waistband! The return route is choking shut!{feed_tag}")
                elif min_clear < caution_threshold:
                    print(f"[Canary] Flaps nervously with low, anxious chirps. Passage narrowing.{feed_tag}")
                else:
                    print("[Canary] Preens its feathers with calm, melodic chirping.")
                    
            print(f"[Right Arm Hair] Common {game.hair_common} | Core(Pink) {game.hair_core} | Mantle(Purple) {game.hair_mantle}")
            if game.seg_tumor[pos] > 0 and game.seg_density[pos] < 500:
                print(">> [TUMOR DETECTED] A bizarre throbbing tumor lump rolls at your feet!")
            print("=" * 80)
            
            print("[1] Tear and eat front flesh")
            if target_seg < SEG_COUNT and game.seg_density[target_seg] < 500:
                print("[2] Step forward 1 step")
            if pos > 0:
                print("[3] Step backward 1 step")
            else:
                print("[3] Return to safe restroom")
            if game.seg_tumor[pos] > 0 and game.seg_density[pos] < 500:
                print("[4] Pick up tumor from ground")
                print("[5] Chew and swallow tumor whole")
            print("[6] Tools")
            print("[7] Change Posture")
            print("[8] Wait")
            print("[9] Look Behind")
        else:
            shell_name = "핵" if pos < CORE_SEGS else ("맨틀" if pos < MANTLE_SEGS else "지표면")
            t_name = TISSUE_NAMES_KO.get(game.seg_tissue[pos], "살점")
            print("\n" + "=" * 80)
            print(f"[위치] 깊이 {pos * 0.5:.1f}m ({shell_name} - {t_name}) | 경과 시간: {game.game_seconds // 60:02d}:{game.game_seconds % 60:02d}")
            print(f"[상태] 위장: {game.stomach_fill // 100}/{game.get_stomach_capacity() // 100}단위 | 체력: {game.player_hp}/100 | 무기: {ITEM_NAMES_KO.get(game.equipped_right, '맨손')}")
            
            front_d = game.seg_density[target_seg] // 10 if target_seg < SEG_COUNT else 0
            print(f"[통로] 앞쪽 벽 밀도: {front_d}% | 협착: {'위험(감속)' if sq >= 500 else '원활'}")
            
            if game.has_canary:
                fed_early = game.canary_feed_timer > 0
                feed_tag = " (먹이 효과)" if fed_early else ""
                warn_threshold = 350 if fed_early else 200
                caution_threshold = 650 if fed_early else 500
                if min_clear < warn_threshold:
                    print(f"[카나리아] 허리춤에서 비명을 지르며 펄럭인다. 뒤쪽이 막혀온다.{feed_tag}")
                elif min_clear < caution_threshold:
                    print(f"[카나리아] 불안하게 파닥거리며 낮게 지저귄다. 통로가 좁아지고 있다.{feed_tag}")
                else:
                    print("[카나리아] 깃털을 고르며 차분하게 지저귄다.")
                    
            print(f"[오른팔 털] 공통 {game.hair_common} | 핵(분홍) {game.hair_core} | 맨틀(보라) {game.hair_mantle}")
            if game.seg_tumor[pos] > 0 and game.seg_density[pos] < 500:
                print(">> [종양 발견] 발치에 파내어진 기괴한 형태의 종양 덩어리가 뒹굴고 있습니다!")
            print("=" * 80)
            
            print("[1] 앞의 살점을 뜯어 먹으며 파내기")
            if target_seg < SEG_COUNT and game.seg_density[target_seg] < 500:
                print("[2] 앞으로 1걸음 전진하기")
            if pos > 0:
                print("[3] 뒤로 1걸음 후퇴하기")
            else:
                print("[3] 화장실 안으로 복귀하기")
            if game.seg_tumor[pos] > 0 and game.seg_density[pos] < 500:
                print("[4] 바닥의 종양 집어 들기")
                print("[5] 바닥의 종양 씹어 삼키기")
            print("[6] 도구")
            print("[7] 자세 변경")
            print("[8] 대기")
            print("[9] 뒤돌아보기")

        cmd = ask_prompt(game)
        if cmd == "LANG_TOGGLED":
            continue
        if not cmd:
            return "quit"

        if cmd == "1":
            if target_seg >= SEG_COUNT:
                print(">> " + ("No more flesh to dig." if game.lang == 'en' else "더 이상 팔 수 있는 살점이 없습니다."))
                continue
            t_type = game.seg_tissue[target_seg]
            if t_type == TISSUE_MEMBRANE and game.equipped_right not in ("knife", "big_saw") and not game.mut_m[9] and not game.mut_t[6]:
                print("\n>> " + ("[CANNOT DIG] Tough membrane slips through bare hands! Needs knife or sharp jaw mutation." if game.lang == 'en' else "[불가] 질긴 막은 맨손으로 잡히지 않습니다! 날카로운 칼이나 강력한 변이가 필요합니다."))
                continue
            if t_type == TISSUE_DISSOLVED:
                print("\n>> " + ("[CANNOT EAT] Chemically dissolved necrotic flesh cannot be ingested." if game.lang == 'en' else "[불가] 화학 약품에 영구적으로 용해된 살점은 먹을 수 없습니다."))
                continue
            if game.stomach_fill >= (game.get_stomach_capacity() + game.get_overfill_capacity()):
                print("\n>> " + ("[OVERFILLED] Stomach filled right to your throat! Must vomit first." if game.lang == 'en' else "[한계] 위장이 목구멍까지 가득 찼습니다! 토해내야 합니다."))
                continue
                
            chew_ms = game.calc_chew_duration_ms(target_seg)
            cells = 1 + (1 if game.mut_m[7] else 0)
            if game.equipped_right == "big_saw":
                cells = 6
                chew_ms = chew_ms * 150 // 100
                
            game.seg_density[target_seg] = max(0, game.seg_density[target_seg] - cells * 300)
            flesh_gain = cells * 400
            game.stomach_fill += flesh_gain
            game.hands_bloody = True
            
            mult = 1 if target_seg < CORE_SEGS else (2 if target_seg < MANTLE_SEGS else 3)
            weighted = flesh_gain * mult
            if target_seg < CORE_SEGS:
                game.carry_core += weighted
                if game.carry_core >= 5000:
                    game.hair_core += game.carry_core // 5000
                    game.carry_core %= 5000
                    print("\n>> " + ("[MUTATION SIGN] Pink bristling hairs sprout across your right forearm!" if game.lang == 'en' else "[변이 징후] 살점을 먹자 오른팔에 진분홍빛 털이 즉시 돋아났습니다!"))
            elif target_seg < MANTLE_SEGS:
                game.carry_mantle += weighted
                if game.carry_mantle >= 5000:
                    game.hair_mantle += game.carry_mantle // 5000
                    game.carry_mantle %= 5000
                    print("\n>> " + ("[MUTATION SIGN] Bruised purple hairs burst forth along your arm!" if game.lang == 'en' else "[변이 징후] 오른팔에 보랏빛 털이 즉시 돋아났습니다!"))
            else:
                game.carry_surface += weighted
                if game.carry_surface >= 5000:
                    game.hair_surface += game.carry_surface // 5000
                    game.carry_surface %= 5000
                    print("\n>> " + ("[MUTATION SIGN] Vibrant yellow nerve fibers sprout across your arm!" if game.lang == 'en' else "[변이 징후] 오른팔에 샛노란 신경털이 즉시 돋아났습니다!"))
                    
            game.carry_common += weighted
            if game.carry_common >= 15000:
                game.hair_common += game.carry_common // 15000
                game.carry_common %= 15000
                print("\n>> " + ("[MUTATION SIGN] Coarse black common hairs grow on your arm!" if game.lang == 'en' else "[변이 징후] 오른팔에 검고 뻣뻣한 공통 털이 돋아났습니다!"))
                
            game.apply_world_regen(chew_ms)
            _, _, dead = game.calc_pressure_and_crush(chew_ms)
            if dead:
                return "restroom"

        elif cmd == "2" and target_seg < SEG_COUNT and game.seg_density[target_seg] < 500:
            move_ms = 170
            if game.is_crouching:
                move_ms = 330
            if sq >= 500 and not game.mut_m[19] and not game.mut_m[20]:
                move_ms *= 2
                print("\n>> " + ("Squeezed heavily in narrow passage, inching forward slowly..." if game.lang == 'en' else "좁아진 통로에 온몸이 끼여 무겁게 전진합니다..."))
            elif sq >= 500 and game.mut_m[19]:
                move_ms = move_ms * 77 // 100
                print("\n>> " + ("M19 Peristaltic Crawl slides smoothly through the constriction!" if game.lang == 'en' else "M19 연동 기기로 비좁은 통로를 미끄러지듯 빠르게 파고듭니다!"))
                
            game.player_pos_seg += 1
            if game.player_pos_seg >= SURFACE_SEGS:
                print("\n" + "=" * 80)
                if game.lang == 'en':
                    print(" [ENDING] You burst through the outer dermis onto sunlit city asphalt!")
                    print(" The colossal human sphere rolls softly away into the skyscrapers with distant humming.")
                else:
                    print(" [엔딩] 바깥 껍질을 뚫고 햇빛이 내리쬐는 도시 길바닥으로 탈출했습니다!")
                    print(" 거대한 인간 구체가 평화로운 노랫소리와 함께 빌딩 숲으로 굴러갑니다.")
                print("================================================================================\n")
                return "ending"
                
            game.apply_world_regen(move_ms)
            _, _, dead = game.calc_pressure_and_crush(move_ms)
            if dead:
                return "restroom"

        elif cmd == "3":
            if pos == 0:
                print("\n>> " + ("Pushed open the door and returned to the clean white restroom." if game.lang == 'en' else "화장실 문을 열고 깨끗한 하얀 타일 방 안으로 돌아왔습니다."))
                game.last_checked_clear = -1
                return "restroom"
            else:
                if game.seg_density[pos - 1] >= 800:
                    print("\n>> " + ("[BLOCKED!] Passage behind has regenerated solid! Must turn and dig back." if game.lang == 'en' else "[위험!] 뒤쪽 통로가 재생으로 꽉 막혀버렸습니다! 뒤쪽을 파내야 합니다."))
                    continue
                move_ms = 170
                if game.is_crouching:
                    move_ms = 330
                if sq >= 500 and not game.mut_m[19] and not game.mut_m[20]:
                    move_ms *= 2
                game.player_pos_seg -= 1
                game.apply_world_regen(move_ms)
                _, _, dead = game.calc_pressure_and_crush(move_ms)
                if dead:
                    return "restroom"

        elif cmd == "4" and game.seg_tumor[pos] > 0 and game.seg_density[pos] < 500:
            if len(game.carried_tumors) >= (2 if game.has_tumor_bag else 1):
                print("\n>> " + ("Cannot carry more tumors! Without a bag, you only have one hand." if game.lang == 'en' else "더 이상 종양을 들 수 없습니다! 가방이 없으면 한 손에 하나만 들 수 있습니다."))
            else:
                game.carried_tumors.append(game.seg_tumor[pos])
                game.seg_tumor[pos] = 0
                print("\n>> " + ("Picked up pulsating tumor! (Flush down toilet for massive teeth settlement)" if game.lang == 'en' else "박동하는 종양을 집어 들었습니다! (화장실 변기에 넣으면 대량의 이빨 정산 가능)"))

        elif cmd == "5" and game.seg_tumor[pos] > 0 and game.seg_density[pos] < 500:
            game.seg_tumor[pos] = 0
            game.tumor_points += 1
            game.tumors_eaten += 1
            if game.lang == 'en':
                print("\n>> Crunch-! Swallowed the squirming tumor whole!")
                print("   A prominent bump bulges out from your belly. (Burst in front of mirror)")
            else:
                print("\n>> 콰직-! 꿈틀거리는 종양을 통째로 씹어 삼켰습니다!")
                print("   배 한가운데에서 불룩한 혹이 밀려 올라왔습니다. (거울 앞에서 터뜨릴 수 있습니다)")

        elif cmd == "6":
            print("\n" + (" [TOOLS]" if game.lang == 'en' else " [도구]"))
            if game.lang == 'en':
                print(f"[1] Deploy Spreader Barrier (Left: {game.item_barriers})")
                print(f"[2] Spray Surface Dissolve (Uses: {game.item_spray_cheap})")
                if game.has_canary and game.item_canary_feed > 0:
                    print(f"[3] Feed Canary (Left: {game.item_canary_feed})")
                print("[0] Back")
            else:
                print(f"[1] 확장 방벽 설치 (남은 개수: {game.item_barriers})")
                print(f"[2] 표면 용해 스프레이 분사 (남은 횟수: {game.item_spray_cheap})")
                if game.has_canary and game.item_canary_feed > 0:
                    print(f"[3] 카나리아에게 먹이 주기 (남은 개수: {game.item_canary_feed})")
                print("[0] 돌아가기")

            sub = ask_prompt(game)
            if sub == "LANG_TOGGLED":
                continue
            if not sub or sub == "0":
                continue

            if sub == "1" and game.item_barriers > 0:
                game.item_barriers -= 1
                game.seg_barrier_hp[pos] = 12000
                print("\n>> " + ("Clank-! Spreader barrier deployed, physically holding back flesh regeneration in this segment!" if game.lang == 'en' else "철컹-! 확장 방벽을 설치하여 이 구역의 재생을 틀어막았습니다!"))
            elif sub == "2" and game.item_spray_cheap > 0:
                game.item_spray_cheap -= 1
                game.seg_tissue[target_seg] = TISSUE_DISSOLVED
                game.seg_density[target_seg] = 0
                print("\n>> " + ("Hiss-! Sprayed acid, permanently dissolving forward flesh!" if game.lang == 'en' else "치익-! 화학 스프레이를 뿌려 앞쪽 살점을 영구적으로 녹였습니다!"))
            elif sub == "3" and game.has_canary and game.item_canary_feed > 0:
                game.item_canary_feed -= 1
                game.canary_feed_timer = 120
                if game.lang == 'en':
                    print("\n>> Fed special seeds to the canary in your waistband.")
                    print("   It pecks greedily, eyes shining alertly with heightened warning sensitivity! (120s)")
                else:
                    print("\n>> 허리춤의 카나리아에게 먹이를 건넸습니다.")
                    print("   카나리아가 낟알을 쪼아먹고 눈을 초롱초롱 빛내며 더욱 민감하게 반응하기 시작했습니다! (120초간 조기 경고)")

        elif cmd == "7":
            game.is_crouching = not game.is_crouching
            if game.lang == 'en':
                print(f"\n>> Switched posture to {'Crouched' if game.is_crouching else 'Standing'}.")
            else:
                print(f"\n>> 자세를 {'웅크린 자세' if game.is_crouching else '선 자세'}로 변경했습니다.")

        elif cmd == "8":
            print("\n>> " + ("Held breath and observed surroundings quietly... (1.0s elapsed)" if game.lang == 'en' else "숨을 죽이고 가만히 상황을 살핍니다... (1.0초 경과)"))
            game.apply_world_regen(1000)
            _, _, dead = game.calc_pressure_and_crush(1000)
            if dead:
                return "restroom"

        elif cmd == "9":
            print("\n>> " + ("Turned head to inspect the return tunnel behind..." if game.lang == 'en' else "뒤쪽으로 고개를 돌려 파온 통로를 살핍니다..."))
            game.apply_world_regen(1000)
            _, min_c, dead = game.calc_pressure_and_crush(1000)
            if dead:
                return "restroom"
            if min_c >= 500:
                print(">> " + ("[Return Passage] Faint fluorescent light from the toilet doorway is visible. The path remains wide open." if game.lang == 'en' else "[뒤쪽 통로] 화장실 문틈의 형광등 불빛이 희미하게 보인다. 통로는 아직 넓게 뚫려 있다."))
            elif min_c >= 200:
                print(">> " + ("[Return Passage] Surrounding flesh is swelling, tightening the excavated walls." if game.lang == 'en' else "[뒤쪽 통로] 주변의 살점들이 부풀어 오르며 굴착된 벽면이 좁혀지고 있다."))
            elif min_c > 0:
                print(">> " + ("[Return Passage] Crimson flesh walls are closing shut! Restroom doorway light is nearly blocked!" if game.lang == 'en' else "[뒤쪽 통로] 핏빛 살벽이 으스러지듯 닫혀가고 있다! 화장실 빛이 거의 보이지 않는다."))
            else:
                print(">> " + ("[Return Passage] Tunnel completely choked shut with dense flesh! Must excavate anew to return!" if game.lang == 'en' else "[뒤쪽 통로] 뒤쪽 통로가 완전히 차올라 막혔다! 귀환하려면 다시 파내야 한다."))


def run_game():
    game = GameState()
    print("================================================================================")
    print("                      구르는 인간 구체와 살구덩이")
    print("               The Rolling Human Sphere & The Flesh Pit")
    print("                       [언어 전환 단축키: 'L']")
    print("================================================================================")
    
    current_scene = "restroom"
    while True:
        if current_scene == "restroom":
            print("\n" + "=" * 80)
            if game.lang == 'en':
                print(" [SAFE ZONE : RESTROOM]")
                print(f" [Teeth in Tank] {game.teeth_in_tank} | [Teeth in Hand] {game.teeth_in_hand}")
                print(f" [Stomach Flesh] {game.stomach_fill // 100}/{game.get_stomach_capacity() // 100} units | [Bowl Flesh] {game.bowl_flesh // 100} units")
                print(f" [Waistband] {'Canary tucked' if game.has_canary else 'Empty'} | [Hand Tool] {ITEM_NAMES_EN.get(game.equipped_right, 'Bare Hands')}")
                print("=" * 80)
                print("[1] Approach toilet")
                print("[2] Check water tank")
                print("[3] Approach sink & mirror")
                print("[4] Inspect dark hole under sink")
                print("[5] Look up at exhaust vent")
                print("[9] Open flesh door and begin expedition")
                print("[L] Toggle Language (한국어 / English)")
                print("[0] Quit Game")
            else:
                print(" [안전지대 : 화장실]")
                print(f" [물탱크 속 이빨] {game.teeth_in_tank}개 | [손에 쥔 이빨] {game.teeth_in_hand}개")
                print(f" [위장 속 살점] {game.stomach_fill // 100}/{game.get_stomach_capacity() // 100}단위 | [변기 속 살점] {game.bowl_flesh // 100}단위")
                print(f" [허리춤] {'카나리아 장착' if game.has_canary else '비어 있음'} | [손 무기] {ITEM_NAMES_KO.get(game.equipped_right, '맨손')}")
                print("=" * 80)
                print("[1] 변기로 다가가기")
                print("[2] 물탱크 확인")
                print("[3] 세면대 다가가기")
                print("[4] 세면대 아래 구석 살피기")
                print("[5] 환풍구 올려다보기")
                print("[9] 살점 문을 열고 굴착 원정 시작하기")
                print("[L] 언어 전환 (한국어 / English)")
                print("[0] 게임 종료")
            
            cmd = ask_prompt(game)
            if cmd == "LANG_TOGGLED":
                continue
            if not cmd or cmd == "0":
                print("\n" + ("Exiting game." if game.lang == 'en' else "게임을 종료합니다."))
                break
                
            if cmd == "1":
                run_toilet_menu(game)
            elif cmd == "2":
                run_tank_menu(game)
            elif cmd == "3":
                run_mirror_menu(game)
            elif cmd == "4":
                print("\n" + (" [Dark Hole under Sink]" if game.lang == 'en' else " [세면대 아래 구석 구멍]"))
                if game.has_canary:
                    print("[1] " + ("Release canary back into hole" if game.lang == 'en' else "카나리아 놓아주기"))
                else:
                    print("[1] " + ("Lie prone, reach arm in, tuck canary into underwear waistband" if game.lang == 'en' else "엎드려 카나리아 한 마리 꺼내 팬티 허리춤에 끼우기"))
                print("[0] " + ("Back" if game.lang == 'en' else "돌아가기"))
                
                sub = ask_prompt(game)
                if sub == "LANG_TOGGLED":
                    continue
                if sub == "1":
                    if game.has_canary:
                        game.has_canary = False
                        print(">> " + ("Gently released canary back into the dark hole." if game.lang == 'en' else "카나리아를 부드럽게 감싸 쥐어 어두운 구멍 안으로 돌려보냈습니다."))
                    else:
                        if game.lang == 'en':
                            print(">> Lay prone on the tile floor, sliding your right arm deep into the dark hole... (5.6s)")
                            print("   Fingertips meet soft, warm feathers and tiny frantic heartbeats. Carefully took one out.")
                            print("   No cage. Pulled underwear waistband elastic and tucked the bird safely inside.")
                            game.has_canary = True
                            print(">> Tucked canary in waistband. It will chirp to warn if your return path narrows.")
                        else:
                            print(">> 바닥에 엎드려 어두운 구멍 안으로 오른팔을 천천히 밀어 넣었습니다... (5.6초 소요)")
                            print("   손가락 끝에 작고 따뜻한 깃털 온기가 닿아 조심스럽게 한 마리를 꺼냈습니다.")
                            print("   새장은 없습니다. 팬티 허리춤 고무줄을 당겨 새를 끼워 넣었습니다.")
                            game.has_canary = True
                            print(">> 카나리아를 허리춤에 끼웠습니다. 복귀 통로가 좁아지면 울음소리로 알립니다.")
            elif cmd == "5":
                run_vent_menu(game)
            elif cmd == "9":
                if game.lang == 'en':
                    print("\n>> Slowly pushed open the restroom door.")
                    print("   Beyond the doorframe, a moist red wall of flesh throbs in rhythmic breathing.")
                else:
                    print("\n>> 화장실 문을 천천히 밀어 열었습니다.")
                    print("   문틀 너머로 붉고 축축한 살점 벽이 숨을 쉬듯 가로막고 있습니다.")
                game.player_pos_seg = 0
                res = run_tunnel_expedition(game)
                if res == "ending" or res == "quit":
                    break
                current_scene = "restroom"


if __name__ == "__main__":
    run_game()
