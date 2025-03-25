import pandas as pd
import numpy as np
import os
import matplotlib.pyplot as plt
from scipy.spatial.distance import euclidean
from fastdtw import fastdtw


def load_data(file_path):
    """CSV 파일을 로드합니다."""
    try:
        data = pd.read_csv(file_path)
        print(f"파일 불러오기 성공: {file_path}")
        print(f"데이터 크기: {data.shape}")
        return data
    except Exception as e:
        print(f"파일 로드 오류 ({file_path}): {e}")
        return None


def extract_time_series(data):
    """시계열 특징을 추출합니다. 바리에이션에 강건한 특징 위주로 추출합니다."""
    # DOT 센서 데이터 찾기
    dot_acc_cols = [col for col in data.columns if "DOT_Acc" in col]
    dot_gyro_cols = [col for col in data.columns if "DOT_Gyro" in col]
    dot_euler_cols = [col for col in data.columns if "DOT_Euler" in col]

    time_series = {}

    # 자이로스코프 데이터 - 패턴 중심 추출
    if dot_gyro_cols and len(dot_gyro_cols) >= 3:
        gyro_x = data[dot_gyro_cols[0]].values
        gyro_y = data[dot_gyro_cols[1]].values
        gyro_z = data[dot_gyro_cols[2]].values

        # 원본 데이터
        time_series["gyro"] = np.column_stack([gyro_x, gyro_y, gyro_z])

        # 1. 스무딩 적용 - 노이즈 감소 및 일관성 증가
        window = 5  # 스무딩 윈도우 크기
        gyro_x_smooth = np.convolve(gyro_x, np.ones(window) / window, mode="valid")
        gyro_y_smooth = np.convolve(gyro_y, np.ones(window) / window, mode="valid")
        gyro_z_smooth = np.convolve(gyro_z, np.ones(window) / window, mode="valid")
        time_series["gyro_smooth"] = np.column_stack(
            [gyro_x_smooth, gyro_y_smooth, gyro_z_smooth]
        )

        # 2. 특징적 패턴 추출 (미분값)
        gyro_x_diff = np.diff(gyro_x, prepend=gyro_x[0])
        gyro_y_diff = np.diff(gyro_y, prepend=gyro_y[0])
        gyro_z_diff = np.diff(gyro_z, prepend=gyro_z[0])
        time_series["gyro_diff"] = np.column_stack(
            [gyro_x_diff, gyro_y_diff, gyro_z_diff]
        )

        # 3. 정규화된 패턴 형태 (크기에 무관)
        gyro_magnitude = np.sqrt(gyro_x**2 + gyro_y**2 + gyro_z**2)
        gyro_magnitude[gyro_magnitude == 0] = 1  # 0으로 나누기 방지
        gyro_x_norm = gyro_x / gyro_magnitude
        gyro_y_norm = gyro_y / gyro_magnitude
        gyro_z_norm = gyro_z / gyro_magnitude
        time_series["gyro_pattern"] = np.column_stack(
            [gyro_x_norm, gyro_y_norm, gyro_z_norm]
        )

    # 가속도 데이터 - 상대적 변화 중심으로 추출
    if dot_acc_cols and len(dot_acc_cols) >= 3:
        acc_x = data[dot_acc_cols[0]].values
        acc_y = data[dot_acc_cols[1]].values
        acc_z = data[dot_acc_cols[2]].values

        # 1. 첫 샘플 대비 상대적 변화 (위치 무관성)
        acc_x_rel = acc_x - acc_x[0]
        acc_y_rel = acc_y - acc_y[0]
        acc_z_rel = acc_z - acc_z[0]
        time_series["acc_relative"] = np.column_stack([acc_x_rel, acc_y_rel, acc_z_rel])

        # 2. 방향 패턴 (크기와 위치에 무관)
        acc_magnitude = np.sqrt(acc_x**2 + acc_y**2 + acc_z**2)
        acc_magnitude[acc_magnitude == 0] = 1  # 0으로 나누기 방지
        acc_x_norm = acc_x / acc_magnitude
        acc_y_norm = acc_y / acc_magnitude
        acc_z_norm = acc_z / acc_magnitude
        time_series["acc_direction"] = np.column_stack(
            [acc_x_norm, acc_y_norm, acc_z_norm]
        )

    # 오일러 각도 데이터 - 각도 변화 패턴 중심
    if dot_euler_cols and len(dot_euler_cols) >= 3:
        roll = data[dot_euler_cols[0]].values
        pitch = data[dot_euler_cols[1]].values
        yaw = data[dot_euler_cols[2]].values

        # 1. 첫 샘플 대비 상대적 변화
        roll_rel = roll - roll[0]
        pitch_rel = pitch - pitch[0]
        yaw_rel = yaw - yaw[0]
        time_series["euler_relative"] = np.column_stack([roll_rel, pitch_rel, yaw_rel])

        # 2. 각도 변화량 (미분값)
        roll_diff = np.diff(roll, prepend=roll[0])
        pitch_diff = np.diff(pitch, prepend=pitch[0])
        yaw_diff = np.diff(yaw, prepend=yaw[0])
        time_series["euler_diff"] = np.column_stack([roll_diff, pitch_diff, yaw_diff])

        # 3. 롤과 피치 패턴 (요우 제외 - 방향성 문제)
        time_series["roll_pitch"] = np.column_stack([roll, pitch])

    # 테스트 데이터의 다운샘플링 (패턴 일관성 향상)
    for key in list(time_series.keys()):
        if key != "length" and len(time_series[key]) > 100:
            # 100 포인트로 다운샘플링 (긴 데이터의 일관성을 위해)
            indices = np.linspace(0, len(time_series[key]) - 1, 100).astype(int)
            time_series[key] = time_series[key][indices]

    # 데이터 길이 정보도 추가
    time_series["length"] = len(data)

    return time_series


def extract_features(data):
    """DTW 결과 분석에 도움이 되는 기본 특징을 추출합니다."""
    features = {}

    # DOT 센서 데이터 찾기
    dot_acc_cols = [col for col in data.columns if "DOT_Acc" in col]
    dot_gyro_cols = [col for col in data.columns if "DOT_Gyro" in col]
    dot_euler_cols = [col for col in data.columns if "DOT_Euler" in col]

    # 자이로스코프 데이터 처리
    if dot_gyro_cols and len(dot_gyro_cols) >= 3:
        gyro_x = data[dot_gyro_cols[0]].values
        gyro_y = data[dot_gyro_cols[1]].values
        gyro_z = data[dot_gyro_cols[2]].values

        # 기본 특성
        features["dot_gyro_z_sum"] = np.sum(gyro_z)
        features["dot_gyro_z_cumsum"] = np.cumsum(np.abs(gyro_z))[-1]

    # 오일러 각도 데이터 처리
    if dot_euler_cols and len(dot_euler_cols) >= 3:
        roll = data[dot_euler_cols[0]].values
        pitch = data[dot_euler_cols[1]].values
        yaw = data[dot_euler_cols[2]].values

        # 기본 변화량
        features["dot_roll_change"] = np.max(roll) - np.min(roll)
        features["dot_pitch_change"] = np.max(pitch) - np.min(pitch)
        features["dot_yaw_change"] = np.max(yaw) - np.min(yaw)

        # 시작-끝 차이
        features["dot_roll_end_diff"] = roll[-1] - roll[0]
        features["dot_pitch_end_diff"] = pitch[-1] - pitch[0]
        features["dot_yaw_end_diff"] = yaw[-1] - yaw[0]

    return features


def collect_reference_data(folder_path):
    """각 동작 유형별 참조 데이터를 수집합니다."""
    reference_data = {}

    # 각 동작 폴더 처리
    for motion_id in range(1, 8):
        motion_path = os.path.join(folder_path, str(motion_id))
        reference_data[motion_id] = []

        # 해당 동작의 폴더가 있는 경우
        if os.path.exists(motion_path):
            print(f"\n== 동작 {motion_id} 참조 데이터 수집 중 ==")

            csv_files = [
                f for f in os.listdir(motion_path) if f.endswith("_merged.csv")
            ]
            for file in csv_files:
                file_path = os.path.join(motion_path, file)
                print(f"파일 처리 중: {file}")

                data = load_data(file_path)
                if data is not None:
                    # 시계열 데이터 추출
                    time_series = extract_time_series(data)
                    reference_data[motion_id].append(time_series)

        # 세션 파일에서 찾기
        else:
            print(f"폴더 {motion_path}가 없음, 세션 파일에서 찾는 중...")
            session_files = [
                f
                for f in os.listdir(folder_path)
                if f.startswith(f"session{motion_id}_") and f.endswith("_merged.csv")
            ]

            for file in session_files:
                file_path = os.path.join(folder_path, file)
                print(f"파일 처리 중: {file}")

                data = load_data(file_path)
                if data is not None:
                    # 시계열 데이터 추출
                    time_series = extract_time_series(data)
                    reference_data[motion_id].append(time_series)

    # 참조 데이터가 비어있는 동작 제외
    empty_motions = [k for k, v in reference_data.items() if not v]
    for k in empty_motions:
        del reference_data[k]

    print(f"\n수집된 참조 데이터: {len(reference_data)}개 동작 유형")
    for motion_id, data_list in reference_data.items():
        print(f"동작 {motion_id}: {len(data_list)}개 샘플")

    return reference_data


def dtw_distance(ts1, ts2):
    """두 시계열 간의 DTW 거리를 계산합니다."""
    try:
        distance, _ = fastdtw(ts1, ts2, dist=euclidean)
        return distance
    except Exception as e:
        print(f"DTW 거리 계산 오류: {e}")
        return float("inf")  # 오류 발생 시 무한대 거리 반환


def normalize_time_series(ts):
    """시계열 데이터를 정규화합니다."""
    mean = np.mean(ts, axis=0)
    std = np.std(ts, axis=0)
    std[std == 0] = 1.0  # 0으로 나누기 방지
    return (ts - mean) / std


def classify_with_dtw(
    test_time_series, reference_data, use_normalized=True, weigh_by_type=True
):
    """DTW를 사용하여 테스트 데이터를 분류합니다. 고유 동작 특성에 맞게 가중치 조정."""
    min_distances = {}

    # 시계열 유형별 가중치 - 각 동작 고유의 특성을 더 잘 반영하도록 조정
    type_weights = {
        "gyro_pattern": 1.2,  # 중요도 상향 (1.0 -> 1.2)
        "gyro_smooth": 0.9,
        "euler_relative": 1.1,  # 중요도 상향 (0.95 -> 1.1) - 손목 젖힘/회전 구분에 중요
        "roll_pitch": 1.1,  # 중요도 상향 (0.95 -> 1.1) - 2번 3번 구분에 필수
        "acc_direction": 0.9,
        "euler_diff": 0.9,  # 중요도 상향 (0.8 -> 0.9)
        "gyro_diff": 0.9,  # 중요도 상향 (0.8 -> 0.9)
        "gyro": 0.7,
        "acc_relative": 0.6,
    }

    # 동작별 패널티 가중치 조정
    motion_weights = {
        1: 0.8,  # 동작 1에 유리한 가중치 (기본 형태를 더 쉽게 인식)
        2: 1.0,  # 동작 2는 중립적 가중치
        3: 1.0,  # 동작 3은 중립적 가중치
        4: 0.9,  # 동작 4는 약간 유리하게 (손목 굽힘 동작이 잘 인식되도록)
        5: 1.0,  # 동작 5는 중립적 가중치
        6: 1.0,  # 동작 6은 중립적 가중치
        7: 1.0,  # 동작 7은 중립적 가중치 (이전에 불리했으나 조정)
    }

    # 신뢰도 정보 저장
    confidence_scores = {}
    pattern_matches = {}

    test_length = test_time_series.get("length", 0)
    print(f"테스트 데이터 길이: {test_length}")

    for motion_id, reference_list in reference_data.items():
        distances = []
        pattern_match_scores = []

        for ref_idx, ref_ts in enumerate(reference_list):
            type_distances = {}

            # 사용 가능한 모든 시계열 유형에 대해 계산
            for ts_type in type_weights.keys():
                if ts_type in test_time_series and ts_type in ref_ts:
                    test_data = test_time_series[ts_type]
                    ref_data = ref_ts[ts_type]

                    # 데이터 정규화
                    if use_normalized:
                        test_data = normalize_time_series(test_data)
                        ref_data = normalize_time_series(ref_data)

                    # DTW 거리 계산
                    dist = dtw_distance(test_data, ref_data)
                    type_distances[ts_type] = dist

            # 가중 평균 계산
            if type_distances:
                # 패턴 유사성 점수 (특징적 패턴 유형에 대한 일치도)
                pattern_types = ["gyro_pattern", "acc_direction", "euler_relative"]
                pattern_score = 0
                if any(t in type_distances for t in pattern_types):
                    pattern_dists = [
                        type_distances[t] for t in pattern_types if t in type_distances
                    ]
                    pattern_score = 1.0 / (1.0 + np.mean(pattern_dists))
                pattern_match_scores.append(pattern_score)

                if weigh_by_type:
                    weighted_sum = sum(
                        type_distances[t] * type_weights[t] for t in type_distances
                    )
                    weight_sum = sum(type_weights[t] for t in type_distances)
                    avg_dist = weighted_sum / weight_sum
                else:
                    avg_dist = sum(type_distances.values()) / len(type_distances)

                distances.append(avg_dist)

        # 이 동작 유형의 최소 거리
        if distances:
            min_idx = np.argmin(distances)
            min_distances[motion_id] = distances[min_idx]

            # 패턴 매칭 점수
            if pattern_match_scores:
                pattern_matches[motion_id] = max(pattern_match_scores)
                # 거리와 패턴 매칭 점수를 결합한 신뢰도 점수
                confidence = (
                    1.0 / (1.0 + min_distances[motion_id]) * pattern_matches[motion_id]
                )
                confidence_scores[motion_id] = confidence

    # 최소 거리를 가진 동작 유형 선택
    if min_distances:
        # 가중치 적용
        for motion_id in list(min_distances.keys()):
            if motion_id in motion_weights:
                print(f"동작 {motion_id}에 가중치 {motion_weights[motion_id]} 적용")
                min_distances[motion_id] *= motion_weights[motion_id]
                # 신뢰도 점수도 조정
                if motion_id in confidence_scores:
                    confidence_scores[motion_id] /= motion_weights[motion_id]

        # 각 동작 유형별 DTW 거리와 신뢰도 출력
        print("\n== 각 동작 유형별 분석 ==")
        for motion_id in sorted(min_distances.keys(), key=lambda k: min_distances[k]):
            confidence = confidence_scores.get(motion_id, 0)
            pattern = pattern_matches.get(motion_id, 0)
            print(
                f"동작 {motion_id}: 거리={min_distances[motion_id]:.4f}, 패턴={pattern:.4f}, 신뢰도={confidence:.4f}"
            )

        # 신뢰도 기반 선택 (거리가 비슷한 경우 패턴 매칭 점수가 높은 것 선택)
        if confidence_scores:
            best_confidence = max(confidence_scores.items(), key=lambda x: x[1])
            best_distance = min(min_distances.items(), key=lambda x: x[1])

            # 거리 차이가 20% 이내면 신뢰도가 높은 것 선택
            if min_distances[best_confidence[0]] < best_distance[1] * 1.2:
                best_motion_id = best_confidence[0]
                print(
                    f"신뢰도 기반 선택: 동작 {best_motion_id} (신뢰도: {best_confidence[1]:.4f})"
                )
            else:
                best_motion_id = best_distance[0]
                print(
                    f"거리 기반 선택: 동작 {best_motion_id} (거리: {best_distance[1]:.4f})"
                )

            return best_motion_id, f"동작 {best_motion_id}"
        else:
            # 기존 방식 (최소 거리)
            best_motion_id = min(min_distances, key=min_distances.get)
            return best_motion_id, f"동작 {best_motion_id}"

    # 참조 데이터가 없는 경우
    print("주의: 참조 데이터가 없습니다. 기본값 반환")
    return 1, "기본 형태 (참조 데이터 없음)"


def visualize_time_series(time_series, title="시계열 데이터"):
    """시계열 데이터를 시각화합니다."""
    types = [t for t in time_series.keys() if t != "length"]  # 'length' 키 제외
    n_types = len(types)

    if n_types == 0:
        print("시각화할 시계열 데이터가 없습니다.")
        return

    fig, axes = plt.subplots(n_types, 1, figsize=(12, 4 * n_types))

    if n_types == 1:
        axes = [axes]

    for i, ts_type in enumerate(types):
        data = time_series[ts_type]
        n_dims = data.shape[1]

        for dim in range(n_dims):
            axes[i].plot(data[:, dim], label=f"차원 {dim+1}")

        axes[i].set_title(f"{ts_type} 데이터")
        axes[i].set_xlabel("시간")
        axes[i].set_ylabel("값")
        axes[i].legend()
        axes[i].grid(True, alpha=0.3)

    plt.suptitle(title)
    plt.tight_layout()
    # plt.savefig(f"{title.replace(' ', '_')}.png")
    # print(f"{title} 시각화가 저장되었습니다.")


if __name__ == "__main__":
    folder_path = "/Users/yoosehyeok/Documents/RecordingData"

    # 1. 참조 데이터 수집
    print("== 참조 데이터 수집 중... ==")
    reference_data = collect_reference_data(folder_path)

    # 참조 데이터 부재 시 사용자에게 안내
    if not reference_data:
        print("\n주의: 참조 데이터를 찾을 수 없습니다!")
        print("각 동작별로 다음 폴더 구조가 필요합니다:")
        print("  /Documents/RecordingData/1/  (동작 1 폴더)")
        print("  /Documents/RecordingData/2/  (동작 2 폴더)")
        print("  ...등")
        print("또는 session1_*.csv, session2_*.csv 등의 파일이 필요합니다.")
        exit(1)

    # 2. 테스트 파일 분류 시작
    print("\n== DTW 기반 테스트 파일 분류 시작 ==")

    # 테스트 파일 목록 설정
    import glob

    test_files = []

    # test*.csv 파일 먼저 찾기
    test_csv_files = glob.glob(os.path.join(folder_path, "test*.csv"))
    if test_csv_files:
        test_files.extend(test_csv_files)

    # 지정된 테스트 파일이 없으면 session*.csv 파일 중 참조 데이터에 포함되지 않은 것만 처리
    if not test_files:
        all_session_files = glob.glob(os.path.join(folder_path, "session*_merged.csv"))
        # 참조 데이터에 사용된 파일 확인을 위한 세트 생성
        reference_files = set()
        for motion_files in reference_data.values():
            for motion_file in motion_files:
                if hasattr(motion_file, "file_path"):
                    reference_files.add(motion_file.file_path)

        # 참조 데이터에 포함되지 않은 세션 파일만 테스트 파일로 사용
        for file_path in all_session_files:
            if file_path not in reference_files:
                test_files.append(file_path)

    if test_files:
        print(f"\n발견된 테스트 파일: {len(test_files)}개")

        # 테스트 결과 저장
        test_results = {}

        # 파일명 정렬 함수 (숫자를 기준으로 자연스럽게 정렬)
        def natural_sort_key(s):
            import re
            # 파일 이름에서 숫자 추출을 위한 함수
            def atoi(text):
                return int(text) if text.isdigit() else text
            
            # 파일 이름을 문자와 숫자로 분할하여 정렬키 생성
            return [atoi(c) for c in re.split(r'(\d+)', os.path.basename(s))]
        
        # 자연스러운 정렬 순서로 테스트 파일 정렬 (1, 2, ..., 10, 11, ...)
        sorted_test_files = sorted(test_files, key=natural_sort_key)
        
        # 각 테스트 파일 처리
        for index, test_file in enumerate(sorted_test_files, 1):
            file_name = os.path.basename(test_file)
            print(f"\n===== 테스트 파일 #{index}: {file_name} =====")

            # DTW 분류 실행
            data = load_data(test_file)
            if data is not None:
                test_time_series = extract_time_series(data)
                motion_id, motion_desc = classify_with_dtw(test_time_series, reference_data)

                # 결과 저장
                test_results[file_name] = (motion_id, motion_desc, index)  # 인덱스도 함께 저장
                print(f"DTW 분류 결과: 동작 {motion_id} ({motion_desc})")

                # 기본 특징값 표시
                features = extract_features(data)
                
                # 중요 특징 그룹화하여 일부만 표시
                print("\n== 주요 특징값 ==")
                important_features = [
                    "dot_gyro_z_sum",
                    "dot_gyro_z_cumsum",
                    "dot_pitch_change",
                    "dot_pitch_end_diff",
                    "dot_roll_change",
                    "dot_roll_end_diff",
                    "dot_yaw_change",
                    "dot_yaw_end_diff",
                ]

                for feature in important_features:
                    if feature in features:
                        print(f"{feature}: {features[feature]:.4f}")
            else:
                print(f"파일을 로드할 수 없습니다: {test_file}")

        # 전체 결과 요약 - 테스트 순서대로 정렬
        print("\n\n========== 테스트 결과 요약 ==========")
        
        # 인덱스 순으로 결과 정렬
        sorted_results = sorted(test_results.items(), key=lambda x: x[1][2])
        
        for file_name, (motion_id, motion_desc, index) in sorted_results:
            print(f"#{index:02d}: {file_name} - 동작 {motion_id} ({motion_desc})")
    else:
        print("테스트 파일을 찾을 수 없습니다.")

    print("\n========== 분류 완료 ==========")