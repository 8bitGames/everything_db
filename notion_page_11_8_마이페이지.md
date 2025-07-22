# 📚 목차

  - 8 마이페이지
    - 81 마이페이지 메인
      - 화면 구성
      - 데이터베이스 상호작용
      - 기능 및 로직
      - UIUX 구현 상세

---

## 👤 8. 마이페이지

### 🏠 **8.1 마이페이지 메인**

#### **화면 구성**
- **프로필 헤더**
  - 프로필 이미지
  - 이름, 인플루언서 인증 마크
  - 보유 포인트 표시

- **메뉴 목록**
  - 내 정보 관리
  - 포인트 관리
  - 내가 추천한 친구들
  - 공지사항
  - 1:1 문의
  - 자주 묻는 질문
  - 설정
  - 로그아웃

#### **데이터베이스 상호작용**
> 💾 **데이터베이스 쿼리**
> ```sql
-- 사용자 프로필 및 통계 조회
SELECT u.name, u.profile_image_url, u.is_influencer, u.available_points,
       u.total_referrals, u.successful_referrals,
       COUNT(DISTINCT r.id) as total_reservations,
       COUNT(DISTINCT r.id) FILTER (WHERE r.status = 'completed') as completed_reservations
FROM public.users u
LEFT JOIN public.reservations r ON u.id = r.user_id
WHERE u.id = auth.uid()
GROUP BY u.id;

-- 읽지 않은 공지사항 수
SELECT COUNT(*) FROM public.announcements 
WHERE is_active = true 
  AND starts_at <= NOW() 
  AND (ends_at IS NULL OR ends_at > NOW())
  AND 'user' = ANY(target_user_type);
> ```

#### **기능 및 로직**
1. **프로필 이미지 관리**
   - Supabase Storage에 이미지 업로드
   - 이미지 압축 및 최적화

2. **인플루언서 상태 표시**
   - `is_influencer` 플래그 기반
   - 인증 마크 아이콘 표시

#### **UI/UX 구현 상세**
- 🎯 **프로필 헤더**:
  - 🌈 **배경**: 그라데이션 또는 패턴 배경
  - 🖼️ **프로필 이미지**: `CircleAvatar` + 테두리, 탭 시 확대 뷰
  - **인플루언서 배지**: `Badge` 위젯 + 금색 크라운 아이콘
  - **포인트**: `AnimatedContainer` + `CountUp` 효과

- 🃏 **통계 카드**:
  - ⚏ **그리드**: `GridView.count` (2x2), 각 통계별 카드
  - **애니메이션**: 진입 시 `staggered` 애니메이션
  - **아이콘**: 각 항목별 컬러 아이콘 (예약, 추천, 포인트 등)

- 📋 **메뉴 리스트**:
  - `ListView` + `ListTile`, 각 항목별 아이콘
  - **화살표**: 우측 `Icon`, 탭 시 회전 애니메이션
  - **배지**: 읽지 않은 공지사항 개수 표시
  - 📦 **섹션 분리**: `Divider` 또는 여백으로 그룹 구분

- **로그아웃**: `AlertDialog`로 확인, 위험한 액션 강조


---

