import asyncio
import websockets
import datetime
import signal
import sys
import socket
import os
import pandas as pd
import numpy as np
import glob
import shutil
from datetime import datetime

# 전역 변수: 현재 워치와 DOT 세션 파일명과 세션 번호
current_watch_file = None
current_dot_file = None
session_active = False

def get_ip_address():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip

# 세션 번호를 확인해서 삭제 되더라도 1부터 시작
def get_next_session_number():
    base_dir = "/Users/yoosehyeok/Documents/RecordingData"
    if not os.path.exists(base_dir):
        os.makedirs(base_dir)
        print("RecordingData 폴더가 없어 새로 생성하고 세션 1부터 시작")
        return 1
    
    # 세션 파일 검색
    all_files = []
    all_files.extend(glob.glob(os.path.join(base_dir, "session*_*.csv")))  # 메인 폴더
    all_files.extend(glob.glob(os.path.join(base_dir, "raw", "session*_*.csv")))  # raw 폴더
    
    if not all_files:
        print("기존 세션 파일 없음: 세션 1부터 시작")
        return 1  # 파일이 없을 경우 1부터 시작
    
    # 파일 이름에서 세션 번호 추출
    session_numbers = []
    for file_path in all_files:
        filename = os.path.basename(file_path)
        print(f"파일 발견: {filename}")
        # "session숫자_" 패턴에서 숫자 부분 추출
        if filename.startswith("session"):
            try:
                num_str = filename.split("_")[0][7:]  # "session" 제거 후 첫 번째 "_" 이전까지
                session_number = int(num_str)
                session_numbers.append(session_number)
                print(f"  - 세션 번호 추출: {session_number}")
            except (ValueError, IndexError) as e:
                print(f"  - 번호 추출 실패: {e}")
                continue
    
    if not session_numbers:
        print("유효한 세션 번호를 찾을 수 없음: 세션 1부터 시작")
        return 1
    
    # 가장 높은 세션 번호 + 1 반환
    next_number = max(session_numbers) + 1
    print(f"발견된 세션 번호들: {sorted(session_numbers)}")
    print(f"다음 세션 번호로 {next_number} 사용")
    return next_number

# 기존 데이터 이동 함수
def ensure_raw_directory():
    base_dir = "/Users/yoosehyeok/Documents/RecordingData"
    raw_dir = os.path.join(base_dir, "RawData")
    
    if not os.path.exists(raw_dir):
        os.makedirs(raw_dir)
        print(f"원본 파일 저장용 RawData 디렉토리 생성됨: {raw_dir}")
    
    return raw_dir

def move_to_raw_directory(file_path):
    """파일을 raw 디렉토리로 이동"""
    if not os.path.exists(file_path):
        print(f"이동할 파일이 존재하지 않습니다: {file_path}")
        return False
    
    raw_dir = ensure_raw_directory()
    filename = os.path.basename(file_path)
    new_path = os.path.join(raw_dir, filename)
    
    try:
        shutil.move(file_path, new_path)
        print(f"파일 이동 완료: {file_path} → {new_path}")
        return True
    except Exception as e:
        print(f"파일 이동 실패: {e}")
        return False

def new_session_files():
    # 매 세션 시작마다 파일 시스템을 확인하여 다음 세션 번호를 결정
    global current_watch_file, current_dot_file, session_active
    
    # 중요: 매 호출마다 새로운 세션 번호 계산 (파일 삭제 반영)
    session_number = get_next_session_number()
    print(f"새로운 세션 시작: 세션 번호 {session_number}")
    
    session_active = True  # 세션 활성화 플래그 설정
    base_dir = "/Users/yoosehyeok/Documents/RecordingData"
    if not os.path.exists(base_dir):
        os.makedirs(base_dir)
    
    # 각각의 파일 이름 생성: sessionN_watch.csv, sessionN_dot.csv
    watch_filename = os.path.join(base_dir, f"session{session_number}_watch.csv")
    dot_filename = os.path.join(base_dir, f"session{session_number}_dot.csv")
    
    current_watch_file = watch_filename
    current_dot_file = dot_filename

    # 워치 CSV 헤더만 작성
    with open(current_watch_file, "w") as file:
        file.write("Timestamp,Acc_X,Acc_Y,Acc_Z,Gyro_X,Gyro_Y,Gyro_Z\n")
    # DOT CSV 헤더만 작성
    with open(current_dot_file, "w") as file:
        file.write("Timestamp,Acc_X,Acc_Y,Acc_Z,Gyro_X,Gyro_Y,Gyro_Z,Euler_Roll,Euler_Pitch,Euler_Yaw,Quat_W,Quat_X,Quat_Y,Quat_Z\n")
    print(f"새로운 세션 파일 생성됨:\n 워치: {current_watch_file}\n DOT: {current_dot_file}")

# 새로 추가된 함수: 두 CSV 파일을 동기화하여 하나로 병합
def merge_sensor_files(watch_file, dot_file):
    try:
        # 기존 파일 존재 확인
        if not os.path.exists(watch_file) or not os.path.exists(dot_file):
            print(f"병합 실패: 파일이 누락되었습니다. ({watch_file} 또는 {dot_file})")
            return None
        
        # 1. 워치와 DOT 파일 읽기
        watch_df = pd.read_csv(watch_file, parse_dates=['Timestamp'])
        dot_df = pd.read_csv(dot_file, parse_dates=['Timestamp'])
        
        if watch_df.empty or dot_df.empty:
            print("병합 실패: 데이터가 비어있습니다.")
            return None
        
        print(f"워치 데이터: {len(watch_df)}행, DOT 데이터: {len(dot_df)}행")
        
        # 2. 워치 데이터 첫 타임스탬프 확인
        watch_first_timestamp = watch_df['Timestamp'].min()
        print(f"워치 첫 타임스탬프: {watch_first_timestamp}")
        
        # 3. DOT 데이터에서 워치 첫 타임스탬프와 가장 가까운 시간 찾기
        closest_dot_index = (dot_df['Timestamp'] - watch_first_timestamp).abs().idxmin()
        closest_dot_timestamp = dot_df.loc[closest_dot_index, 'Timestamp']
        print(f"워치 시작과 가장 가까운 DOT 타임스탬프: {closest_dot_timestamp}")
        
        # 시간 차이 계산 (디버깅 용도)
        time_diff = (closest_dot_timestamp - watch_first_timestamp).total_seconds()
        print(f"시간 차이: {time_diff:.3f}초")
        
        # 4. 워치 첫 타임스탬프 이후의 DOT 데이터만 필터링 
        # (또는 워치 시작보다 약간 이전 시점으로 설정할 수도 있음)
        start_time = closest_dot_timestamp
        
        # 만약 DOT 데이터가 워치보다 늦게 시작한다면, 워치 시작 시간을 사용
        if closest_dot_timestamp > watch_first_timestamp:
            start_time = watch_first_timestamp
            
        # 공통 종료 시간 결정
        end_time = min(watch_df['Timestamp'].max(), dot_df['Timestamp'].max())
        
        # 5. 공통 구간으로 필터링
        watch_df = watch_df[(watch_df['Timestamp'] >= start_time) & (watch_df['Timestamp'] <= end_time)]
        dot_df = dot_df[(dot_df['Timestamp'] >= start_time) & (dot_df['Timestamp'] <= end_time)]
        
        print(f"공통 시간대 필터링 후: 워치 데이터 {len(watch_df)}행, DOT 데이터 {len(dot_df)}행")
        
        # 6. DOT 데이터의 타임스탬프를 인덱스로 설정
        dot_df.set_index('Timestamp', inplace=True)
        
        # 결과 데이터프레임 초기화 (DOT 데이터 기준)
        result_df = pd.DataFrame(index=dot_df.index)
        
        # DOT 데이터 열 추가 (접두사 붙임)
        for col in dot_df.columns:
            result_df[f'DOT_{col}'] = dot_df[col]
        
        # 7. 가장 가까운 워치 데이터 찾기
        print("가장 가까운 워치 데이터 매핑 중...")
        
        # 워치 데이터 결과물 준비
        watch_result = pd.DataFrame(index=result_df.index)
        
        # 번거롭지만 모든 DOT 타임스탬프에 대해 가장 가까운 워치 데이터 찾기
        for timestamp in result_df.index:
            # 가장 가까운 워치 데이터 찾기
            closest_idx = (watch_df['Timestamp'] - timestamp).abs().idxmin()
            closest_row = watch_df.loc[closest_idx]
            
            # 워치 데이터의 모든 열을 추가
            for col in watch_df.columns:
                if col != 'Timestamp':
                    watch_result.loc[timestamp, f'Watch_{col}'] = closest_row[col]
        
        # 8. 두 결과를 병합
        result_df = result_df.join(watch_result)
        
        # 타임스탬프를 열로 복원
        result_df.reset_index(inplace=True)
        result_df.rename(columns={'index': 'Timestamp'}, inplace=True)
        
        # 9. 결과 파일 저장
        base_dir = os.path.dirname(watch_file)
        session_num = os.path.basename(watch_file).split('_')[0]
        merged_file = os.path.join(base_dir, f"{session_num}_merged.csv")
        result_df.to_csv(merged_file, index=False, date_format='%Y-%m-%d %H:%M:%S.%f')
        
        print(f"동기화 병합 완료: {merged_file} (타임라인 {len(result_df)}행)")
        
        # 10. 원본 파일을 raw 디렉토리로 이동
        move_to_raw_directory(watch_file)
        move_to_raw_directory(dot_file)
        
        return merged_file
        
    except Exception as e:
        import traceback
        print(f"파일 병합 중 오류 발생: {str(e)}")
        print(traceback.format_exc())  # 상세한 오류 내용 출력
        return None

async def handle_connection(websocket, path=None):
    global current_watch_file, current_dot_file, session_active
    async for message in websocket:
        print(f"수신 메시지: {message}")
        if message == "SESSION_START":
            # 파일이 없으면 생성
            if current_watch_file is None and current_dot_file is None:
                new_session_files()
        elif message == "SESSION_END":
            print("세션 종료 명령 수신 - 1초 대기 후 파일 종료")
            await asyncio.sleep(1.5)
            
            # 세션 종료 전 파일 병합 작업 수행
            watch_file = current_watch_file
            dot_file = current_dot_file
            
            # 파일을 닫기 전에 병합 시도
            if watch_file and dot_file:
                print("세션 파일 병합 작업 시작...")
                merged_file = merge_sensor_files(watch_file, dot_file)
                if merged_file:
                    print(f"병합 파일 생성 완료: {merged_file}")
                else:
                    print("병합 실패: 작업을 완료할 수 없습니다.")
            
            current_watch_file = None
            current_dot_file = None
            session_active = False  # 세션 비활성화 플래그 설정
            
        elif not session_active:
            # 세션이 활성화되지 않았으면 데이터를 저장하지 않고 무시
            print("활성 세션이 없습니다. 수신된 데이터가 무시됩니다.")
        else:
            # 기존 데이터 처리 코드 유지
            if message.startswith("WATCH:"):
                # 워치 센서 데이터 저장 (접두어 제거)
                if current_watch_file is not None:
                    row = message[6:].rstrip("\n")  # "WATCH:" 제거
                    
                    # 데이터 검증: 워치 데이터는 7개 열로만 구성
                    row_parts = row.split(',')
                    if len(row_parts) > 7:  # 타임스탬프 + 6개 센서값
                        row = ','.join(row_parts[:7])  # 앞 7개 열만 사용
                    
                    with open(current_watch_file, "a") as file:
                        file.write(row + "\n")
            elif message.startswith("DOT:"):
                # DOT 센서 데이터 저장 (접두어 제거)
                if current_dot_file is not None:
                    row = message[4:].rstrip("\n")  # "DOT:" 제거
                    
                    # 데이터 검증: DOT 데이터는 14개 열로만 구성
                    row_parts = row.split(',')
                    if len(row_parts) > 14:  # 타임스탬프 + 13개 센서값
                        row = ','.join(row_parts[:14])  # 앞 14개 열만 사용
                    
                    with open(current_dot_file, "a") as file:
                        file.write(row + "\n")
            else:
                # 기존 호환성 코드도 열 개수 검증 추가
                trimmed = message.lstrip()
                if trimmed and trimmed[0].isdigit():
                    # 워치 센서 데이터로 간주
                    if current_watch_file is not None:
                        row = message.rstrip("\n")
                        row_parts = row.split(',')
                        if len(row_parts) > 7:
                            row = ','.join(row_parts[:7])
                        with open(current_watch_file, "a") as file:
                            file.write(row + "\n")
                else:
                    # DOT 센서 데이터로 간주
                    if current_dot_file is not None:
                        row = message.rstrip("\n")
                        row_parts = row.split(',')
                        if len(row_parts) > 14:
                            row = ','.join(row_parts[:14])
                        with open(current_dot_file, "a") as file:
                            file.write(row + "\n")

async def main():
    # raw 디렉토리 함수 호출
    ensure_raw_directory()
    
    ip_address = get_ip_address()
    server = await websockets.serve(handle_connection, "0.0.0.0", 5678)
    print(f"WebSocket server is running on ws://{ip_address}:5678")

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, server.close)

    await server.wait_closed()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("서버가 종료되었습니다.")