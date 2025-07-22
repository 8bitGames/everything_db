-- =============================================
-- 에뷰리띵 앱 - SUPABASE 데이터베이스 구조 (MVP)
-- EBEAUTYTHING APP - SUPABASE DATABASE STRUCTURE (MVP)
-- Version: 3.3 - Simplified for MVP (No Social Feed, No Reviews)
-- Based on PRD.txt, Flutter Development Guide, and Web Admin Guide
-- =============================================

-- PostgreSQL 확장 기능 활성화
-- PostGIS: 위치 기반 서비스 (내 주변 샵 찾기, 거리 계산)를 위해 필수
-- UUID: 보안성과 확장성을 위해 모든 Primary Key에 UUID 사용
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- =============================================
-- ENUMS (열거형 타입)
-- =============================================

-- 사용자 관련 ENUM
-- 성별 선택: 회원가입 화면에서 다양한 성별 옵션 제공 (개인정보보호법 준수)
CREATE TYPE user_gender AS ENUM ('male', 'female', 'other', 'prefer_not_to_say');

-- 사용자 상태: 계정 관리 및 보안을 위한 상태 구분
-- active: 정상 사용자, inactive: 비활성, suspended: 정지, deleted: 탈퇴 (소프트 삭제)
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'suspended', 'deleted');

-- 사용자 역할: 권한 기반 접근 제어 및 기능 구분
-- user: 일반 사용자, shop_owner: 샵 사장, admin: 관리자, influencer: 인플루언서
CREATE TYPE user_role AS ENUM ('user', 'shop_owner', 'admin', 'influencer');

-- 소셜 로그인 제공자: 소셜 로그인 화면에서 지원하는 플랫폼들
CREATE TYPE social_provider AS ENUM ('kakao', 'apple', 'google', 'email');

-- 샵 관련 ENUM
-- 샵 상태: 샵 운영 상태 관리 및 노출 제어
-- pending_approval: 신규 입점 대기, active: 운영중, inactive: 임시 중단
CREATE TYPE shop_status AS ENUM ('active', 'inactive', 'pending_approval', 'suspended', 'deleted');

-- 샵 타입: PRD 2.1 정책에 따른 입점샵/비입점샵 구분으로 노출 순서 결정
-- partnered: 입점샵 (우선 노출), non_partnered: 비입점샵
CREATE TYPE shop_type AS ENUM ('partnered', 'non_partnered');

-- 서비스 카테고리: 앱에서 제공하는 뷰티 서비스 분류
-- hair는 향후 확장을 위해 정의하되 현재는 비활성화 상태
CREATE TYPE service_category AS ENUM ('nail', 'eyelash', 'waxing', 'eyebrow_tattoo', 'hair');

-- 샵 인증 상태: 입점 심사 과정 관리
CREATE TYPE shop_verification_status AS ENUM ('pending', 'verified', 'rejected');

-- 예약 관련 ENUM
-- 예약 상태: 예약 플로우 전체 과정을 추적하고 각 상태별 UI 표시
-- requested: 예약 요청됨, confirmed: 샵에서 확정, completed: 서비스 완료
CREATE TYPE reservation_status AS ENUM ('requested', 'confirmed', 'completed', 'cancelled_by_user', 'cancelled_by_shop', 'no_show');

-- 결제 상태: 토스페이먼츠 연동 및 예약금/잔금 분할 결제 지원
-- deposit_paid: 예약금만 결제, fully_paid: 전액 결제 완료
CREATE TYPE payment_status AS ENUM ('pending', 'deposit_paid', 'fully_paid', 'refunded', 'partially_refunded', 'failed');

-- 결제 수단: 토스페이먼츠 및 간편결제 옵션 지원
CREATE TYPE payment_method AS ENUM ('toss_payments', 'kakao_pay', 'naver_pay', 'card', 'bank_transfer');

-- 포인트 관련 ENUM
-- 포인트 거래 유형: PRD 2.4, 2.5 정책에 따른 포인트 적립/사용 추적
-- earned_service: 서비스 이용 적립 (2.5%), earned_referral: 추천 적립
CREATE TYPE point_transaction_type AS ENUM ('earned_service', 'earned_referral', 'used_service', 'expired', 'adjusted', 'influencer_bonus');

-- 포인트 상태: 7일 제한 규칙 적용을 위한 상태 관리
-- pending: 7일 대기중, available: 사용 가능, used: 사용됨, expired: 만료됨
CREATE TYPE point_status AS ENUM ('pending', 'available', 'used', 'expired');

-- 알림 관련 ENUM
-- 알림 타입: 앱 내 다양한 알림 상황에 대응
CREATE TYPE notification_type AS ENUM ('reservation_confirmed', 'reservation_cancelled', 'point_earned', 'referral_success', 'system');

-- 알림 상태: 알림 목록 화면에서 읽음/읽지않음 표시
CREATE TYPE notification_status AS ENUM ('unread', 'read', 'deleted');

-- 신고 관련 ENUM
-- 신고 사유: 컨텐츠 모더레이션을 위한 신고 카테고리
CREATE TYPE report_reason AS ENUM ('spam', 'inappropriate_content', 'harassment', 'other');

-- 관리자 액션 ENUM
-- 관리자 작업 로그: 웹 관리자 대시보드에서 수행된 작업 추적
CREATE TYPE admin_action_type AS ENUM ('user_suspended', 'shop_approved', 'shop_rejected', 'refund_processed', 'points_adjusted');

-- =============================================
-- 핵심 테이블들 (CORE TABLE
-- =============================================

-- 사용자 테이블 (Supabase auth.users 확장)
-- Supabase Auth와 연동하여 소셜 로그인 정보와 앱 내 프로필 정보를 통합 관리
-- 추천인 시스템(PRD 2.2)과 포인트 시스템(PRD 2.4, 2.5) 지원을 위한 필드들 포함
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) UNIQUE,
    phone_number VARCHAR(20) UNIQUE, -- PASS 본인인증에서 받은 전화번호
    phone_verified BOOLEAN DEFAULT FALSE, -- 전화번호 인증 완료 여부
    name VARCHAR(100) NOT NULL, -- 실명 (본인인증 후 받음)
    nickname VARCHAR(50), -- 향후 확장을 위한 닉네임 필드
    gender user_gender, -- 회원가입 시 선택한 성별
    birth_date DATE, -- 생년월일 (타겟 광고 및 통계용)
    profile_image_url TEXT, -- Supabase Storage에 저장된 프로필 이미지
    user_role user_role DEFAULT 'user', -- 권한 구분
    user_status user_status DEFAULT 'active', -- 계정 상태
    is_influencer BOOLEAN DEFAULT FALSE, -- 인플루언서 자격 여부 (PRD 2.2)
    influencer_qualified_at TIMESTAMPTZ, -- 인플루언서 자격 획득 일시
    social_provider social_provider, -- 소셜 로그인 제공자
    social_provider_id VARCHAR(255), -- 소셜 로그인 고유 ID
    referral_code VARCHAR(20) UNIQUE, -- 개인 추천 코드 (자동 생성)
    referred_by_code VARCHAR(20), -- 가입 시 입력한 추천인 코드
    total_points INTEGER DEFAULT 0, -- 총 적립 포인트 (성능 최적화용 비정규화)
    available_points INTEGER DEFAULT 0, -- 사용 가능한 포인트 (7일 제한 적용 후)
    total_referrals INTEGER DEFAULT 0, -- 총 추천한 친구 수
    successful_referrals INTEGER DEFAULT 0, -- 결제까지 완료한 추천 친구 수
    last_login_at TIMESTAMPTZ, -- 마지막 로그인 시간
    terms_accepted_at TIMESTAMPTZ, -- 이용약관 동의 일시 (법적 요구사항)
    privacy_accepted_at TIMESTAMPTZ, -- 개인정보처리방침 동의 일시
    marketing_consent BOOLEAN DEFAULT FALSE, -- 마케팅 정보 수신 동의
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 사용자 설정 테이블
-- 알림 설정 화면과 기타 설정들을 위한 별도 테이블
-- users 테이블과 분리하여 설정 변경 시 메인 테이블 업데이트 최소화
CREATE TABLE public.user_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    push_notifications_enabled BOOLEAN DEFAULT TRUE, -- 푸시 알림 전체 ON/OFF
    reservation_notifications BOOLEAN DEFAULT TRUE, -- 예약 관련 알림
    event_notifications BOOLEAN DEFAULT TRUE, -- 이벤트 알림
    marketing_notifications BOOLEAN DEFAULT FALSE, -- 마케팅 알림
    location_tracking_enabled BOOLEAN DEFAULT TRUE, -- 위치 추적 허용
    language_preference VARCHAR(10) DEFAULT 'ko', -- 언어 설정
    currency_preference VARCHAR(3) DEFAULT 'KRW', -- 통화 설정
    theme_preference VARCHAR(20) DEFAULT 'light', -- 테마 설정 (향후 다크모드)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- 샵 정보 테이블
-- 홈 화면의 "내 주변 샵" 기능과 샵 상세 화면을 위한 핵심 테이블
-- PostGIS의 GEOGRAPHY 타입으로 위치 기반 검색 최적화
CREATE TABLE public.shops (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID REFERENCES public.users(id) ON DELETE SET NULL, -- 샵 사장님 계정
    name VARCHAR(255) NOT NULL, -- 샵명
    description TEXT, -- 샵 소개
    phone_number VARCHAR(20), -- 샵 전화번호 (바로 통화 기능)
    email VARCHAR(255), -- 샵 이메일
    address TEXT NOT NULL, -- 주소 (지도 표시용)
    detailed_address TEXT, -- 상세주소
    postal_code VARCHAR(10), -- 우편번호
    latitude DECIMAL(10, 8), -- 위도 (별도 저장으로 호환성 확보)
    longitude DECIMAL(11, 8), -- 경도
    location GEOGRAPHY(POINT, 4326), -- PostGIS 지리정보 (공간 검색 최적화)
    shop_type shop_type DEFAULT 'non_partnered', -- 입점/비입점 구분 (PRD 2.1)
    shop_status shop_status DEFAULT 'pending_approval', -- 운영 상태
    verification_status shop_verification_status DEFAULT 'pending', -- 인증 상태
    business_license_number VARCHAR(50), -- 사업자등록번호
    business_license_image_url TEXT, -- 사업자등록증 이미지 (인증용)
    main_category service_category NOT NULL, -- 주 서비스 카테고리
    sub_categories service_category[], -- 부가 서비스들 (배열로 다중 선택)
    operating_hours JSONB, -- 영업시간 (요일별 오픈/마감 시간)
    payment_methods payment_method[], -- 지원하는 결제 수단들
    kakao_channel_url TEXT, -- 카카오톡 채널 연결 URL
    total_bookings INTEGER DEFAULT 0, -- 총 예약 수 (성능용 비정규화)
    partnership_started_at TIMESTAMPTZ, -- 입점 시작일 (PRD 2.1 노출 순서 결정)
    featured_until TIMESTAMPTZ, -- 추천샵 노출 종료일
    is_featured BOOLEAN DEFAULT FALSE, -- 추천샵 여부
    commission_rate DECIMAL(5,2) DEFAULT 10.00, -- 수수료율 (%)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 샵 이미지 테이블
-- 샵 상세 화면의 이미지 슬라이더를 위한 여러 이미지 저장
-- display_order로 노출 순서 제어 가능
CREATE TABLE public.shop_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL, -- Supabase Storage URL
    alt_text VARCHAR(255), -- 접근성을 위한 대체 텍스트
    is_primary BOOLEAN DEFAULT FALSE, -- 대표 이미지 여부
    display_order INTEGER DEFAULT 0, -- 이미지 노출 순서
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 샵 서비스 테이블
-- 샵 상세 화면의 "서비스 목록" 탭과 예약 시 서비스 선택을 위한 테이블
-- 가격 범위(min/max)로 "₩50,000 ~ ₩80,000" 형태 표시 지원
CREATE TABLE public.shop_services (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL, -- 서비스명 (예: "속눈썹 연장")
    description TEXT, -- 서비스 상세 설명
    category service_category NOT NULL, -- 서비스 카테고리
    price_min INTEGER, -- 최소 가격 (원 단위)
    price_max INTEGER, -- 최대 가격 (원 단위)
    duration_minutes INTEGER, -- 예상 소요 시간 (예약 슬롯 계산용)
    deposit_amount INTEGER, -- 예약금 금액 (고정값)
    deposit_percentage DECIMAL(5,2), -- 예약금 비율 (전체 금액의 %)
    is_available BOOLEAN DEFAULT TRUE, -- 서비스 제공 여부
    booking_advance_days INTEGER DEFAULT 30, -- 사전 예약 가능 일수
    cancellation_hours INTEGER DEFAULT 24, -- 취소 가능 시간 (시간 단위)
    display_order INTEGER DEFAULT 0, -- 서비스 노출 순서
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 서비스 이미지 테이블
-- 각 서비스별 이미지들 (시술 전후 사진 등)
CREATE TABLE public.service_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id UUID NOT NULL REFERENCES public.shop_services(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    alt_text VARCHAR(255),
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 예약 시스템 (RESERVATION SYSTEM)
-- =============================================

-- 예약 테이블
-- 예약 플로우의 핵심 테이블로, 예약 내역 화면과 샵 관리에서 사용
-- reservation_datetime은 GENERATED ALWAYS로 자동 계산하여 시간 기반 쿼리 최적화
CREATE TABLE public.reservations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    reservation_date DATE NOT NULL, -- 예약 날짜
    reservation_time TIME NOT NULL, -- 예약 시간
    reservation_datetime TIMESTAMPTZ GENERATED ALWAYS AS (
        (reservation_date || ' ' || reservation_time)::TIMESTAMPTZ
    ) STORED, -- 날짜+시간 결합 (인덱스 및 정렬용)
    status reservation_status DEFAULT 'requested', -- 예약 상태
    total_amount INTEGER NOT NULL, -- 총 서비스 금액
    deposit_amount INTEGER NOT NULL, -- 결제한 예약금
    remaining_amount INTEGER, -- 현장에서 결제할 잔금
    points_used INTEGER DEFAULT 0, -- 사용한 포인트
    points_earned INTEGER DEFAULT 0, -- 적립될 포인트 (PRD 2.4 - 2.5%)
    special_requests TEXT, -- 특별 요청사항
    cancellation_reason TEXT, -- 취소 사유
    no_show_reason TEXT, -- 노쇼 사유
    confirmed_at TIMESTAMPTZ, -- 샵에서 예약 확정한 시간
    completed_at TIMESTAMPTZ, -- 서비스 완료 시간
    cancelled_at TIMESTAMPTZ, -- 취소된 시간
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 예약-서비스 연결 테이블 (다대다 관계)
-- 한 번 예약에 여러 서비스를 선택할 수 있도록 지원
-- 예약 시점의 가격을 저장하여 나중에 가격이 변경되어도 예약 정보 보존
CREATE TABLE public.reservation_services (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_id UUID NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
    service_id UUID NOT NULL REFERENCES public.shop_services(id) ON DELETE RESTRICT,
    quantity INTEGER DEFAULT 1, -- 동일 서비스 수량
    unit_price INTEGER NOT NULL, -- 예약 시점의 단가
    total_price INTEGER NOT NULL, -- 단가 × 수량
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 결제 거래 테이블
-- 토스페이먼츠 연동과 예약금/잔금 분할 결제 지원
-- provider_transaction_id로 외부 결제사와 매핑
CREATE TABLE public.payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_id UUID NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    payment_method payment_method NOT NULL, -- 결제 수단
    payment_status payment_status DEFAULT 'pending', -- 결제 상태
    amount INTEGER NOT NULL, -- 결제 금액 (원)
    currency VARCHAR(3) DEFAULT 'KRW', -- 통화
    payment_provider VARCHAR(50), -- 결제 제공사 ('toss_payments' 등)
    provider_transaction_id VARCHAR(255), -- 결제사 거래 ID
    provider_order_id VARCHAR(255), -- 결제사 주문 ID
    is_deposit BOOLEAN DEFAULT TRUE, -- 예약금 여부 (true: 예약금, false: 잔금)
    paid_at TIMESTAMPTZ, -- 결제 완료 시간
    refunded_at TIMESTAMPTZ, -- 환불 처리 시간
    refund_amount INTEGER DEFAULT 0, -- 환불 금액
    failure_reason TEXT, -- 결제 실패 사유
    metadata JSONB, -- 결제사별 추가 데이터
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 포인트 시스템 (POINTS SYSTEM)
-- =============================================

-- 포인트 거래 내역 테이블
-- PRD 2.4, 2.5의 포인트 정책 구현을 위한 핵심 테이블
-- available_from으로 7일 제한 규칙 적용
CREATE TABLE public.point_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    reservation_id UUID REFERENCES public.reservations(id) ON DELETE SET NULL, -- 서비스 연관 적립
    transaction_type point_transaction_type NOT NULL, -- 거래 유형
    amount INTEGER NOT NULL, -- 포인트 금액 (적립=양수, 사용=음수)
    description TEXT, -- 거래 설명
    status point_status DEFAULT 'pending', -- 포인트 상태
    available_from TIMESTAMPTZ, -- 사용 가능 시작일 (적립 후 7일)
    expires_at TIMESTAMPTZ, -- 포인트 만료일
    related_user_id UUID REFERENCES public.users(id), -- 추천 관련 포인트의 경우 추천한 사용자
    metadata JSONB, -- 추가 거래 정보
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 포인트 잔액 테이블 (성능 최적화용 구체화 뷰)
-- 포인트 계산이 복잡하므로 별도 테이블로 빠른 조회 지원
CREATE TABLE public.point_balances (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    total_earned INTEGER DEFAULT 0, -- 총 적립 포인트
    total_used INTEGER DEFAULT 0, -- 총 사용 포인트
    available_balance INTEGER DEFAULT 0, -- 현재 사용 가능 포인트
    pending_balance INTEGER DEFAULT 0, -- 7일 대기 중인 포인트
    last_calculated_at TIMESTAMPTZ DEFAULT NOW(), -- 마지막 계산 시간
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 즐겨찾기 (FAVORITES)
-- =============================================

-- 사용자 즐겨찾기 테이블
-- 홈 화면의 "내가 찜한 샵" 섹션을 위한 테이블
-- UNIQUE 제약으로 중복 즐겨찾기 방지
CREATE TABLE public.user_favorites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, shop_id) -- 동일 샵 중복 즐겨찾기 방지
);

-- =============================================
-- 알림 시스템 (NOTIFICATIONS)
-- =============================================

-- 알림 테이블
-- 앱 내 알림 목록과 푸시 알림 발송 이력 관리
-- related_id로 예약, 포인트 등 관련 엔티티 연결
CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    notification_type notification_type NOT NULL, -- 알림 유형
    title VARCHAR(255) NOT NULL, -- 알림 제목
    message TEXT NOT NULL, -- 알림 내용
    status notification_status DEFAULT 'unread', -- 읽음 상태
    related_id UUID, -- 관련 엔티티 ID (예약 ID, 포인트 거래 ID 등)
    action_url TEXT, -- 딥링크 URL (탭 시 이동할 화면)
    scheduled_for TIMESTAMPTZ, -- 예약 알림 발송 시간
    sent_at TIMESTAMPTZ, -- 실제 발송 시간
    read_at TIMESTAMPTZ, -- 읽은 시간
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 푸시 알림 토큰 테이블
-- FCM 토큰 관리로 기기별 푸시 알림 발송
-- 기기 변경이나 앱 재설치 시 토큰 업데이트 대응
CREATE TABLE public.push_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL, -- FCM 토큰
    platform VARCHAR(20) NOT NULL, -- 플랫폼 ('ios', 'android')
    is_active BOOLEAN DEFAULT TRUE, -- 토큰 활성 상태
    last_used_at TIMESTAMPTZ DEFAULT NOW(), -- 마지막 사용 시간
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, token) -- 사용자당 동일 토큰 중복 방지
);

-- =============================================
-- 컨텐츠 모더레이션 & 신고 (CONTENT MODERATION & REPORTING)
-- =============================================

-- 컨텐츠 신고 테이블
-- 향후 피드 기능 및 부적절한 샵/사용자 신고 기능 지원
CREATE TABLE public.content_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, -- 신고자
    reported_content_type VARCHAR(50) NOT NULL, -- 신고 대상 유형 ('shop', 'user')
    reported_content_id UUID NOT NULL, -- 신고 대상 ID
    reason report_reason NOT NULL, -- 신고 사유
    description TEXT, -- 상세 신고 내용
    status VARCHAR(20) DEFAULT 'pending', -- 처리 상태
    reviewed_by UUID REFERENCES public.users(id), -- 검토한 관리자
    reviewed_at TIMESTAMPTZ, -- 검토 완료 시간
    resolution_notes TEXT, -- 처리 결과 메모
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 관리자 & 분석 (ADMIN & ANALYTICS)
-- =============================================

-- 관리자 액션 로그 테이블
-- 웹 관리자 대시보드에서 수행한 모든 관리 작업 기록
-- 감사(Audit) 목적과 관리자 권한 남용 방지
CREATE TABLE public.admin_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT, -- 작업 수행 관리자
    action_type admin_action_type NOT NULL, -- 작업 유형
    target_type VARCHAR(50) NOT NULL, -- 대상 엔티티 유형
    target_id UUID NOT NULL, -- 대상 엔티티 ID
    reason TEXT, -- 작업 사유
    metadata JSONB, -- 추가 작업 정보
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 시스템 설정 & 공용 정책 테이블들 (SYSTEM SETTINGS & POLICIES)
-- =============================================

-- 시스템 전역 설정 테이블
-- 어드민에서 코드 수정 없이 전역 설정값들을 관리
-- key-value 방식으로 다양한 타입의 설정값 저장 가능
CREATE TABLE public.system_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    setting_key VARCHAR(100) UNIQUE NOT NULL, -- 설정 키 (예: 'default_commission_rate')
    setting_value TEXT NOT NULL, -- 설정값 (문자열로 저장 후 타입 변환)
    value_type VARCHAR(20) DEFAULT 'string', -- 값 타입 ('string', 'number', 'boolean', 'json')
    category VARCHAR(50) NOT NULL, -- 설정 카테고리 ('payment', 'point', 'notification' 등)
    description TEXT, -- 설정 설명
    is_active BOOLEAN DEFAULT TRUE, -- 설정 활성화 여부
    created_by UUID REFERENCES public.users(id), -- 설정 생성 관리자
    updated_by UUID REFERENCES public.users(id), -- 설정 수정 관리자
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 간소화: business_policies 제거 (필요한 정책은 system_settings에서 관리)

-- 서비스 카테고리 기본 설정 테이블
-- 카테고리별 기본 예약 정책, 수수료율 등을 중앙 관리
CREATE TABLE public.service_category_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category service_category PRIMARY KEY, -- 서비스 카테고리
    default_commission_rate DECIMAL(5,2) DEFAULT 10.00, -- 카테고리별 기본 수수료율
    default_deposit_percentage DECIMAL(5,2) DEFAULT 30.00, -- 기본 예약금 비율
    default_cancellation_hours INTEGER DEFAULT 24, -- 기본 취소 가능 시간
    default_booking_advance_days INTEGER DEFAULT 30, -- 기본 사전 예약 가능 일수
    min_service_duration INTEGER DEFAULT 30, -- 최소 서비스 시간(분)
    max_service_duration INTEGER DEFAULT 300, -- 최대 서비스 시간(분)
    category_description TEXT, -- 카테고리 설명
    is_active BOOLEAN DEFAULT TRUE, -- 카테고리 활성화 여부
    display_order INTEGER DEFAULT 0, -- 앱에서 표시 순서
    icon_url TEXT, -- 카테고리 아이콘 URL
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 간소화: 복잡한 알림 템플릿 제거 (필요시 코드에서 직접 관리)

-- 앱 버전 및 운영 설정 테이블
-- 앱 업데이트, 점검 모드, 공지사항 등 운영 관련 설정 관리
CREATE TABLE public.app_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    config_key VARCHAR(100) UNIQUE NOT NULL, -- 설정 키
    platform VARCHAR(20) NOT NULL, -- 플랫폼 ('ios', 'android', 'all')
    config_data JSONB NOT NULL, -- 설정 데이터
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES public.users(id),
    updated_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 프로모션 및 이벤트 테이블
-- 할인 쿠폰, 포인트 보너스, 이벤트 등을 어드민에서 관리
CREATE TABLE public.promotions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    promotion_code VARCHAR(50) UNIQUE, -- 프로모션 코드 (쿠폰 등)
    title VARCHAR(255) NOT NULL, -- 프로모션 제목
    description TEXT, -- 프로모션 설명
    promotion_type VARCHAR(50) NOT NULL, -- 유형 ('discount', 'point_bonus', 'free_service' 등)
    target_audience JSONB, -- 대상 사용자 (신규, 기존, 인플루언서 등)
    conditions JSONB, -- 적용 조건 (최소 금액, 특정 카테고리 등)
    benefits JSONB, -- 혜택 내용 (할인율, 포인트 배율 등)
    usage_limit INTEGER, -- 총 사용 제한
    usage_limit_per_user INTEGER DEFAULT 1, -- 사용자당 사용 제한
    current_usage INTEGER DEFAULT 0, -- 현재 사용 횟수
    starts_at TIMESTAMPTZ NOT NULL, -- 프로모션 시작일
    ends_at TIMESTAMPTZ NOT NULL, -- 프로모션 종료일
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES public.users(id),
    updated_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 정산 시스템 (SETTLEMENT SYSTEM)
-- =============================================

-- 정산 주기 및 상태 ENUM
CREATE TYPE settlement_status AS ENUM ('pending', 'processing', 'completed', 'failed', 'cancelled');
CREATE TYPE settlement_period AS ENUM ('weekly', 'bi_weekly', 'monthly');

-- 샵별 정산 설정 테이블
-- 각 샵의 정산 주기, 계좌 정보, 세무 정보 관리
CREATE TABLE public.shop_settlement_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    settlement_period settlement_period DEFAULT 'weekly', -- 정산 주기
    settlement_day INTEGER DEFAULT 1, -- 정산 요일 (1=월요일, 7=일요일) 또는 날짜
    bank_name VARCHAR(100), -- 은행명
    bank_account VARCHAR(50), -- 계좌번호 (암호화 저장 권장)
    account_holder VARCHAR(100), -- 예금주
    business_registration_number VARCHAR(20), -- 사업자등록번호
    tax_invoice_email VARCHAR(255), -- 세금계산서 발행 이메일
    commission_rate DECIMAL(5,2), -- 개별 수수료율 (없으면 기본값 적용)
    minimum_settlement_amount INTEGER DEFAULT 10000, -- 최소 정산 금액
    auto_settlement BOOLEAN DEFAULT TRUE, -- 자동 정산 여부
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(shop_id)
);

-- 정산 배치 테이블 (정산 회차별 정보)
-- 주간/월간 정산을 위한 배치 단위 관리
CREATE TABLE public.settlement_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_name VARCHAR(100) NOT NULL, -- 정산 배치명 (예: "2024년 1월 1주차")
    settlement_period settlement_period NOT NULL, -- 정산 주기
    period_start_date DATE NOT NULL, -- 정산 기간 시작일
    period_end_date DATE NOT NULL, -- 정산 기간 종료일
    total_revenue INTEGER DEFAULT 0, -- 총 매출액
    total_commission INTEGER DEFAULT 0, -- 총 수수료
    total_settlement_amount INTEGER DEFAULT 0, -- 총 정산 금액
    shop_count INTEGER DEFAULT 0, -- 정산 대상 샵 수
    status settlement_status DEFAULT 'pending', -- 배치 상태
    processed_at TIMESTAMPTZ, -- 처리 완료 시간
    created_by UUID REFERENCES public.users(id), -- 처리 관리자
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 샵별 정산 내역 테이블
-- 각 정산 배치에서 샵별 상세 정산 정보
CREATE TABLE public.shop_settlements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    settlement_batch_id UUID NOT NULL REFERENCES public.settlement_batches(id) ON DELETE CASCADE,
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    period_start_date DATE NOT NULL, -- 정산 기간 시작일
    period_end_date DATE NOT NULL, -- 정산 기간 종료일
    total_bookings INTEGER DEFAULT 0, -- 총 예약 건수
    completed_bookings INTEGER DEFAULT 0, -- 완료된 예약 건수
    cancelled_bookings INTEGER DEFAULT 0, -- 취소된 예약 건수
    gross_revenue INTEGER DEFAULT 0, -- 총 매출액 (예약금 + 잔금)
    commission_rate DECIMAL(5,2) NOT NULL, -- 적용된 수수료율
    commission_amount INTEGER DEFAULT 0, -- 수수료 금액
    adjustment_amount INTEGER DEFAULT 0, -- 조정 금액 (환불, 패널티 등)
    net_settlement_amount INTEGER DEFAULT 0, -- 최종 정산 금액 (매출 - 수수료 - 조정)
    tax_amount INTEGER DEFAULT 0, -- 세금 (부가세 등)
    settlement_status settlement_status DEFAULT 'pending', -- 정산 상태
    bank_transfer_amount INTEGER DEFAULT 0, -- 실제 송금 금액
    transfer_fee INTEGER DEFAULT 0, -- 송금 수수료
    settled_at TIMESTAMPTZ, -- 정산 완료 시간
    settlement_notes TEXT, -- 정산 메모
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(settlement_batch_id, shop_id)
);

-- 정산 상세 내역 테이블 (예약별)
-- 정산에 포함된 개별 예약들의 상세 정보
CREATE TABLE public.settlement_details (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    settlement_id UUID NOT NULL REFERENCES public.shop_settlements(id) ON DELETE CASCADE,
    reservation_id UUID NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
    service_amount INTEGER NOT NULL, -- 서비스 금액
    commission_rate DECIMAL(5,2) NOT NULL, -- 수수료율
    commission_amount INTEGER NOT NULL, -- 수수료 금액
    net_amount INTEGER NOT NULL, -- 순수익 (서비스 금액 - 수수료)
    payment_method payment_method NOT NULL, -- 결제 수단
    completed_at TIMESTAMPTZ NOT NULL, -- 서비스 완료 시간
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 정산 관련 통계 (SETTLEMENT STATISTICS - 정산만)
-- =============================================

-- 정산 스케줄 관리 테이블
-- 관리자가 정산 일정을 미리 설정하고 관리
CREATE TABLE public.settlement_schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    schedule_name VARCHAR(100) NOT NULL, -- 스케줄명 (예: "주간 정산")
    settlement_period settlement_period NOT NULL, -- 정산 주기
    schedule_day INTEGER NOT NULL, -- 정산 실행 요일 (1=월요일) 또는 날짜
    schedule_time TIME DEFAULT '15:00', -- 정산 실행 시간
    target_shop_type shop_type, -- NULL이면 전체, 있으면 특정 타입만
    is_active BOOLEAN DEFAULT TRUE, -- 스케줄 활성화 여부
    auto_approve BOOLEAN DEFAULT FALSE, -- 자동 승인 여부 (FALSE면 수동 승인)
    notification_emails TEXT[], -- 정산 완료 시 알림받을 이메일들
    created_by UUID REFERENCES public.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 정산 승인 및 송금 처리 테이블
-- 관리자의 정산 승인부터 실제 송금까지의 전체 프로세스 관리
CREATE TABLE public.settlement_transfers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    settlement_id UUID NOT NULL REFERENCES public.shop_settlements(id) ON DELETE CASCADE,
    transfer_status VARCHAR(50) DEFAULT 'pending_approval', -- 송금 상태
    -- 'pending_approval' → 'approved' → 'transfer_requested' → 'transfer_completed' → 'failed'
    approved_by UUID REFERENCES public.users(id), -- 승인한 관리자
    approved_at TIMESTAMPTZ, -- 승인 시간
    transfer_method VARCHAR(50), -- 송금 방법 ('bank_transfer', 'toss_transfer' 등)
    bank_name VARCHAR(100), -- 송금할 은행
    account_number VARCHAR(50), -- 계좌번호 (암호화 권장)
    account_holder VARCHAR(100), -- 예금주
    transfer_amount INTEGER NOT NULL, -- 실제 송금 금액
    transfer_fee INTEGER DEFAULT 0, -- 송금 수수료
    external_transfer_id VARCHAR(255), -- 외부 송금 서비스 거래 ID
    transfer_requested_at TIMESTAMPTZ, -- 송금 요청 시간
    transfer_completed_at TIMESTAMPTZ, -- 송금 완료 시간
    failure_reason TEXT, -- 송금 실패 사유
    admin_notes TEXT, -- 관리자 메모
    retry_count INTEGER DEFAULT 0, -- 재시도 횟수
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(settlement_id)
);

-- 간소화된 정산 로그 테이블 (핵심 정보만)
CREATE TABLE public.settlement_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    settlement_id UUID NOT NULL REFERENCES public.shop_settlements(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL, -- 액션 ('approved', 'transfer_completed', 'failed')
    performed_by UUID REFERENCES public.users(id), -- 작업 수행자
    notes TEXT, -- 작업 메모
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 정산 및 통계 관련 인덱스들 (INDEXES FOR SETTLEMENT & ANALYTICS)
-- =============================================

-- 정산 관련 인덱스
CREATE INDEX idx_shop_settlements_batch_shop ON public.shop_settlements(settlement_batch_id, shop_id);
CREATE INDEX idx_shop_settlements_status ON public.shop_settlements(settlement_status);
CREATE INDEX idx_shop_settlements_period ON public.shop_settlements(period_start_date, period_end_date);
CREATE INDEX idx_settlement_details_reservation ON public.settlement_details(reservation_id);

-- =============================================
-- 정산 관련 트리거들 (TRIGGERS FOR SETTLEMENT ONLY)
-- =============================================

-- 정산 관련 테이블들에 updated_at 트리거 추가
CREATE TRIGGER update_shop_settlement_configs_updated_at BEFORE UPDATE ON public.shop_settlement_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_settlement_batches_updated_at BEFORE UPDATE ON public.settlement_batches
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_shop_settlements_updated_at BEFORE UPDATE ON public.shop_settlements
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_settlement_schedules_updated_at BEFORE UPDATE ON public.settlement_schedules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_settlement_transfers_updated_at BEFORE UPDATE ON public.settlement_transfers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================
-- 정산 관련 비즈니스 로직 함수들 (SETTLEMENT BUSINESS LOGIC)
-- =============================================

-- 샵별 정산 금액 계산 함수
-- 특정 기간 동안의 완료된 예약들을 기준으로 정산액 계산
CREATE OR REPLACE FUNCTION calculate_shop_settlement(
    shop_uuid UUID,
    start_date DATE,
    end_date DATE
)
RETURNS TABLE(
    gross_revenue INTEGER,
    commission_amount INTEGER,
    net_settlement INTEGER,
    booking_count INTEGER
) AS $$
DECLARE
    commission_rate_val DECIMAL(5,2);
BEGIN
    -- 샵의 수수료율 조회 (개별 설정 또는 기본값)
    SELECT COALESCE(ssc.commission_rate, calculate_commission_rate(shop_uuid))
    INTO commission_rate_val
    FROM public.shop_settlement_configs ssc
    WHERE ssc.shop_id = shop_uuid;
    
    -- 기간 내 완료된 예약들의 정산 정보 계산
    RETURN QUERY
    SELECT 
        SUM(r.total_amount)::INTEGER as gross_revenue,
        FLOOR(SUM(r.total_amount * commission_rate_val / 100))::INTEGER as commission_amount,
        (SUM(r.total_amount) - FLOOR(SUM(r.total_amount * commission_rate_val / 100)))::INTEGER as net_settlement,
        COUNT(*)::INTEGER as booking_count
    FROM public.reservations r
    WHERE r.shop_id = shop_uuid
    AND r.status = 'completed'
    AND r.completed_at::DATE BETWEEN start_date AND end_date;
END;
$$ LANGUAGE plpgsql;

-- 정산 배치 생성 함수
-- 주간/월간 정산을 위한 배치를 생성하고 각 샵별 정산 내역 계산
CREATE OR REPLACE FUNCTION create_settlement_batch(
    period_type settlement_period,
    start_date DATE,
    end_date DATE
)
RETURNS UUID AS $$
DECLARE
    batch_id UUID;
    shop_record RECORD;
    settlement_data RECORD;
    batch_name TEXT;
BEGIN
    -- 배치명 생성
    batch_name := CASE period_type
        WHEN 'weekly' THEN start_date::TEXT || ' ~ ' || end_date::TEXT || ' 주간정산'
        WHEN 'monthly' THEN TO_CHAR(start_date, 'YYYY년 MM월') || ' 월간정산'
        ELSE start_date::TEXT || ' ~ ' || end_date::TEXT || ' 정산'
    END;
    
    -- 정산 배치 생성
    INSERT INTO public.settlement_batches (
        batch_name, settlement_period, period_start_date, period_end_date, status
    ) VALUES (
        batch_name, period_type, start_date, end_date, 'processing'
    ) RETURNING id INTO batch_id;
    
    -- 각 활성 샵에 대해 정산 내역 생성
    FOR shop_record IN 
        SELECT id, name FROM public.shops 
        WHERE shop_status = 'active' 
    LOOP
        -- 샵별 정산 금액 계산
        SELECT * INTO settlement_data 
        FROM calculate_shop_settlement(shop_record.id, start_date, end_date);
        
        -- 정산 데이터가 있는 경우에만 정산 내역 생성
        IF settlement_data.booking_count > 0 THEN
            INSERT INTO public.shop_settlements (
                settlement_batch_id,
                shop_id,
                period_start_date,
                period_end_date,
                completed_bookings,
                gross_revenue,
                -- 여기서 실제 적용된 수수료율을 다시 계산해야 함
                calculate_commission_rate(shop_record.id),
                settlement_data.commission_amount,
                settlement_data.net_settlement
            ) VALUES (
                batch_id,
                shop_record.id,
                start_date,
                end_date,
                settlement_data.booking_count,
                settlement_data.gross_revenue,
                -- 여기서 실제 적용된 수수료율을 다시 계산해야 함
                calculate_commission_rate(shop_record.id),
                settlement_data.commission_amount,
                settlement_data.net_settlement
            );
        END IF;
    END LOOP;
    
    -- 배치 상태를 pending으로 변경
    UPDATE public.settlement_batches 
    SET status = 'pending', updated_at = NOW()
    WHERE id = batch_id;
    
    RETURN batch_id;
END;
$$ LANGUAGE plpgsql;



-- =============================================
-- 공용 설정 관리 함수들 (UTILITY FUNCTIONS FOR SETTINGS)
-- =============================================

-- 간소화된 수수료율 계산 함수
CREATE OR REPLACE FUNCTION calculate_commission_rate(shop_uuid UUID)
RETURNS DECIMAL AS $$
DECLARE
    shop_type_val shop_type;
    commission_rate DECIMAL;
BEGIN
    -- 샵 타입 조회
    SELECT shop_type INTO shop_type_val FROM public.shops WHERE id = shop_uuid;
    
    -- 샵 타입에 따른 수수료율 적용
    IF shop_type_val = 'partnered' THEN
        commission_rate := get_system_setting_number('partnered_commission_rate');
    ELSE
        commission_rate := get_system_setting_number('non_partnered_commission_rate');
    END IF;
    
    RETURN COALESCE(commission_rate, 10.00); -- 기본값 10%
END;
$$ LANGUAGE plpgsql;

-- 시스템 설정값 조회 함수
-- 타입 변환을 자동으로 처리하여 코드에서 쉽게 사용
CREATE OR REPLACE FUNCTION get_system_setting(setting_key_param VARCHAR)
RETURNS TEXT AS $$
DECLARE
    result_value TEXT;
BEGIN
    SELECT setting_value INTO result_value
    FROM public.system_settings 
    WHERE setting_key = setting_key_param AND is_active = TRUE;
    
    RETURN COALESCE(result_value, '');
END;
$$ LANGUAGE plpgsql;

-- 숫자 타입 시스템 설정값 조회 함수
CREATE OR REPLACE FUNCTION get_system_setting_number(setting_key_param VARCHAR)
RETURNS DECIMAL AS $$
DECLARE
    result_value TEXT;
BEGIN
    SELECT setting_value INTO result_value
    FROM public.system_settings 
    WHERE setting_key = setting_key_param AND value_type = 'number' AND is_active = TRUE;
    
    RETURN COALESCE(result_value::DECIMAL, 0);
END;
$$ LANGUAGE plpgsql;

-- 간소화: 복잡한 정책 조회 제거 (system_settings으로 충분)

-- =============================================
-- 공용 설정 테이블 트리거들 (TRIGGERS FOR SETTINGS TABLES)
-- =============================================

-- 설정 테이블들에 updated_at 트리거 추가
CREATE TRIGGER update_system_settings_updated_at BEFORE UPDATE ON public.system_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 간소화: business_policies 관련 트리거 제거됨

CREATE TRIGGER update_service_category_configs_updated_at BEFORE UPDATE ON public.service_category_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 간소화: notification_templates 관련 트리거 제거됨

CREATE TRIGGER update_app_configs_updated_at BEFORE UPDATE ON public.app_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================
-- 앱 공지사항 테이블
-- 마이페이지의 공지사항 기능과 홈 화면 이벤트 배너 지원
-- target_user_type으로 사용자 그룹별 노출 제어
CREATE TABLE public.announcements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL, -- 공지 제목
    content TEXT NOT NULL, -- 공지 내용
    is_important BOOLEAN DEFAULT FALSE, -- 중요 공지 여부
    is_active BOOLEAN DEFAULT TRUE, -- 노출 여부
    target_user_type user_role[], -- 노출 대상 사용자 그룹
    starts_at TIMESTAMPTZ DEFAULT NOW(), -- 노출 시작일
    ends_at TIMESTAMPTZ, -- 노출 종료일
    created_by UUID REFERENCES public.users(id), -- 작성한 관리자
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 자주 묻는 질문 테이블
-- 마이페이지의 FAQ 기능 지원
-- 카테고리별 분류와 조회수/도움됨 통계 수집
CREATE TABLE public.faqs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category VARCHAR(100) NOT NULL, -- FAQ 카테고리 ('예약', '포인트', '계정' 등)
    question TEXT NOT NULL, -- 질문
    answer TEXT NOT NULL, -- 답변
    display_order INTEGER DEFAULT 0, -- 노출 순서
    is_active BOOLEAN DEFAULT TRUE, -- 노출 여부
    view_count INTEGER DEFAULT 0, -- 조회수
    helpful_count INTEGER DEFAULT 0, -- 도움됨 수
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- STORAGE BUCKETS 설정
-- =============================================

-- Supabase Storage 버킷 설정
-- 이미지 업로드 및 관리를 위한 버킷들

/*
-- 프로필 이미지 버킷 (공개)
INSERT INTO storage.buckets (id, name, public) VALUES ('profile-images', 'profile-images', true);

-- 샵 이미지 버킷 (공개) - 샵 상세 화면 이미지 슬라이더용
INSERT INTO storage.buckets (id, name, public) VALUES ('shop-images', 'shop-images', true);

-- 서비스 이미지 버킷 (공개) - 서비스별 이미지들
INSERT INTO storage.buckets (id, name, public) VALUES ('service-images', 'service-images', true);

-- 사업자등록증 등 문서 버킷 (비공개) - 입점 심사용
INSERT INTO storage.buckets (id, name, public) VALUES ('business-documents', 'business-documents', false);
*/

-- =============================================
-- 성능 최적화 인덱스들 (INDEXES FOR PERFORMANCE)
-- =============================================

-- 사용자 테이블 인덱스
-- 추천인 코드와 전화번호는 자주 검색되므로 인덱스 생성
CREATE INDEX idx_users_referral_code ON public.users(referral_code);
CREATE INDEX idx_users_phone_number ON public.users(phone_number);
CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_status ON public.users(user_status); -- 활성 사용자 필터링

-- 샵 테이블 인덱스
-- location은 GIST 인덱스로 공간 검색 최적화 (내 주변 샵 찾기)
CREATE INDEX idx_shops_location ON public.shops USING GIST(location);
CREATE INDEX idx_shops_status ON public.shops(shop_status); -- 활성 샵 필터링
CREATE INDEX idx_shops_type ON public.shops(shop_type); -- 입점/비입점 구분
CREATE INDEX idx_shops_category ON public.shops(main_category); -- 카테고리별 검색

-- 예약 테이블 인덱스
-- 사용자별, 샵별, 날짜별 예약 조회 최적화
CREATE INDEX idx_reservations_user_id ON public.reservations(user_id);
CREATE INDEX idx_reservations_shop_id ON public.reservations(shop_id);
CREATE INDEX idx_reservations_datetime ON public.reservations(reservation_datetime);
CREATE INDEX idx_reservations_status ON public.reservations(status);
CREATE INDEX idx_reservations_date_status ON public.reservations(reservation_date, status); -- 복합 인덱스

-- 포인트 거래 테이블 인덱스
-- 포인트 관리 화면의 내역 조회 최적화
CREATE INDEX idx_point_transactions_user_id ON public.point_transactions(user_id);
CREATE INDEX idx_point_transactions_type ON public.point_transactions(transaction_type);
CREATE INDEX idx_point_transactions_status ON public.point_transactions(status);
CREATE INDEX idx_point_transactions_available_from ON public.point_transactions(available_from); -- 7일 제한 체크

-- 알림 테이블 인덱스
-- 알림 목록 화면의 빠른 로딩을 위한 인덱스
CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_status ON public.notifications(status); -- 읽지 않은 알림 조회
CREATE INDEX idx_notifications_type ON public.notifications(notification_type);

-- =============================================
-- 행 수준 보안 (ROW LEVEL SECURITY - RLS)
-- =============================================

-- 모든 테이블에 RLS 활성화 (보안 강화)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.point_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- 기본 RLS 정책들

-- 사용자는 자신의 데이터만 조회 가능
CREATE POLICY "Users can read own data" ON public.users
    FOR SELECT USING (auth.uid() = id);

-- 사용자는 자신의 데이터만 수정 가능
CREATE POLICY "Users can update own data" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- 사용자는 자신의 설정만 관리 가능
CREATE POLICY "Users can manage own settings" ON public.user_settings
    FOR ALL USING (auth.uid() = user_id);

-- 모든 사용자가 활성 샵 조회 가능 (홈 화면, 검색 기능)
CREATE POLICY "Public can read active shops" ON public.shops
    FOR SELECT USING (shop_status = 'active');

-- 샵 사장은 자신의 샵만 관리 가능
CREATE POLICY "Shop owners can manage own shops" ON public.shops
    FOR ALL USING (auth.uid() = owner_id);

-- 사용자는 자신의 예약만 조회 가능
CREATE POLICY "Users can read own reservations" ON public.reservations
    FOR SELECT USING (auth.uid() = user_id);

-- 샵 사장은 자신의 샵 예약들만 조회 가능
CREATE POLICY "Shop owners can read shop reservations" ON public.reservations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.shops 
            WHERE shops.id = reservations.shop_id 
            AND shops.owner_id = auth.uid()
        )
    );

-- 사용자는 자신의 포인트 거래만 조회 가능
CREATE POLICY "Users can read own point transactions" ON public.point_transactions
    FOR SELECT USING (auth.uid() = user_id);

-- 사용자는 자신의 알림만 조회 가능
CREATE POLICY "Users can read own notifications" ON public.notifications
    FOR SELECT USING (auth.uid() = user_id);

-- =============================================
-- 자동 업데이트 트리거들 (TRIGGERS FOR AUTOMATIC UPDATES)
-- =============================================

-- updated_at 필드 자동 업데이트 함수
-- 데이터 수정 시 타임스탬프 자동 갱신
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 관련 테이블들에 updated_at 트리거 적용
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_settings_updated_at BEFORE UPDATE ON public.user_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_shops_updated_at BEFORE UPDATE ON public.shops
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_reservations_updated_at BEFORE UPDATE ON public.reservations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 사용자 포인트 잔액 자동 업데이트 함수
-- 포인트 거래 발생 시 users 테이블의 포인트 필드들 자동 갱신
-- 성능을 위해 비정규화된 데이터 동기화 유지
CREATE OR REPLACE FUNCTION update_user_points()
RETURNS TRIGGER AS $$
BEGIN
    -- 사용자의 총 포인트와 사용 가능 포인트 업데이트
    UPDATE public.users SET
        total_points = (
            SELECT COALESCE(SUM(amount), 0) 
            FROM public.point_transactions 
            WHERE user_id = NEW.user_id 
            AND amount > 0 
            AND status = 'available'
        ),
        available_points = (
            SELECT COALESCE(SUM(amount), 0) 
            FROM public.point_transactions 
            WHERE user_id = NEW.user_id 
            AND status = 'available'
            AND (available_from IS NULL OR available_from <= NOW()) -- 7일 제한 체크
            AND (expires_at IS NULL OR expires_at > NOW()) -- 만료 체크
        )
    WHERE id = NEW.user_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 포인트 거래 시 잔액 업데이트 트리거
CREATE TRIGGER update_point_balances_trigger 
    AFTER INSERT OR UPDATE ON public.point_transactions
    FOR EACH ROW EXECUTE FUNCTION update_user_points();

-- =============================================
-- 비즈니스 로직 함수들 (FUNCTIONS FOR BUSINESS LOGIC)
-- =============================================

-- 고유한 추천인 코드 생성 함수
-- 8자리 영숫자 조합으로 중복 방지
CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    result TEXT := '';
    i INTEGER;
BEGIN
    FOR i IN 1..8 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
    END LOOP;
    
    -- 중복 코드 체크 후 재귀 호출로 고유성 보장
    IF EXISTS (SELECT 1 FROM public.users WHERE referral_code = result) THEN
        RETURN generate_referral_code(); -- 중복 시 재귀 호출
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- 인플루언서 자격 확인 및 업데이트 함수
-- PRD 2.2 정책: 50명 추천 + 50명 모두 1회 이상 결제 완료
CREATE OR REPLACE FUNCTION check_influencer_status(user_uuid UUID)
RETURNS BOOLEAN AS $$
DECLARE
    referral_count INTEGER;
    paid_referral_count INTEGER;
BEGIN
    -- 총 추천한 친구 수 계산
    SELECT COUNT(*) INTO referral_count
    FROM public.users 
    WHERE referred_by_code = (
        SELECT referral_code FROM public.users WHERE id = user_uuid
    );
    
    -- 추천한 친구 중 1회 이상 결제 완료한 친구 수 계산
    SELECT COUNT(DISTINCT u.id) INTO paid_referral_count
    FROM public.users u
    JOIN public.payments p ON u.id = p.user_id
    WHERE u.referred_by_code = (
        SELECT referral_code FROM public.users WHERE id = user_uuid
    ) AND p.payment_status = 'fully_paid';
    
    -- 인플루언서 자격 조건 충족 시 상태 업데이트
    IF referral_count >= 50 AND paid_referral_count >= 50 THEN
        UPDATE public.users SET
            is_influencer = TRUE,
            influencer_qualified_at = NOW(),
            user_role = 'influencer'
        WHERE id = user_uuid AND NOT is_influencer;
        
        RETURN TRUE;
    END IF;
    
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- 서비스 이용 포인트 적립 함수
-- PRD 2.4 정책: 총 시술 금액의 2.5% 적립, 최대 30만원까지
CREATE OR REPLACE FUNCTION award_service_points(reservation_uuid UUID)
RETURNS INTEGER AS $$
DECLARE
    total_amount INTEGER;
    user_uuid UUID;
    points_to_award INTEGER;
    max_eligible_amount INTEGER := 300000; -- 30만원 한도
    point_rate DECIMAL := 0.025; -- 2.5% 적립률
BEGIN
    -- 예약 정보 조회
    SELECT r.total_amount, r.user_id INTO total_amount, user_uuid
    FROM public.reservations r
    WHERE r.id = reservation_uuid;
    
    -- 포인트 계산 (30만원 한도 적용)
    points_to_award := FLOOR(
        LEAST(total_amount, max_eligible_amount) * point_rate
    );
    
    -- 포인트 거래 내역 생성 (7일 후 사용 가능)
    INSERT INTO public.point_transactions (
        user_id,
        reservation_id,
        transaction_type,
        amount,
        description,
        status,
        available_from
    ) VALUES (
        user_uuid,
        reservation_uuid,
        'earned_service',
        points_to_award,
        '서비스 이용 적립',
        'pending',
        NOW() + INTERVAL '7 days' -- PRD 2.5: 7일 후 사용 가능
    );
    
    RETURN points_to_award;
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- 초기 데이터 (INITIAL DATA)
-- =============================================

-- 기본 관리자 계정 생성 (실제 운영시 업데이트 필요)
INSERT INTO public.users (
    id,
    email,
    name,
    user_role,
    user_status,
    referral_code,
    created_at
) VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    'admin@ebeautything.com',
    'System Admin',
    'admin',
    'active',
    'ADMIN001',
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- 시스템 핵심 설정 초기값들 (간소화된 MVP 버전)
INSERT INTO public.system_settings (setting_key, setting_value, value_type, category, description) VALUES
-- 수수료 관련 설정 (기존 business_policies의 핵심 정책만)
('partnered_commission_rate', '8.00', 'number', 'commission', '입점샵 수수료율 (%)'),
('non_partnered_commission_rate', '10.00', 'number', 'commission', '일반샵 수수료율 (%)'),

-- 포인트 관련 설정
('point_earning_rate', '2.5', 'number', 'point', '포인트 적립률 (%)'),
('point_max_eligible_amount', '300000', 'number', 'point', '포인트 적립 가능 최대 금액 (원)'),
('point_restriction_days', '7', 'number', 'point', '포인트 사용 제한 기간 (일)'),
('influencer_point_bonus_rate', '1.5', 'number', 'point', '인플루언서 포인트 보너스 배율'),

-- 예약 관련 설정
('default_cancellation_hours', '24', 'number', 'reservation', '기본 취소 가능 시간 (시간)'),
('min_deposit_amount', '10000', 'number', 'reservation', '최소 예약금 금액 (원)'),

-- 앱 운영 설정
('app_maintenance_mode', 'false', 'boolean', 'app', '앱 점검 모드'),
('customer_service_phone', '1588-0000', 'string', 'app', '고객센터 전화번호');

-- 자주 묻는 질문 초기 데이터
-- 마이페이지 FAQ 기능을 위한 기본 질문들
INSERT INTO public.faqs (category, question, answer, display_order) VALUES
('예약', '예약을 취소하고 싶어요', '예약 시간 24시간 전까지는 100% 환불이 가능합니다. 마이예약에서 취소 버튼을 눌러주세요.', 1),
('예약', '예약금은 얼마인가요?', '예약금은 샵과 서비스에 따라 다르며, 보통 전체 금액의 20-30% 정도입니다.', 2),
('포인트', '포인트는 언제 사용할 수 있나요?', '포인트는 적립된 날로부터 7일 후에 사용 가능합니다.', 1),
('포인트', '포인트 적립률은 얼마인가요?', '서비스 이용 금액의 2.5%가 포인트로 적립됩니다. (최대 30만원까지)', 2),
('계정', '회원탈퇴는 어떻게 하나요?', '마이페이지 > 설정 > 회원탈퇴에서 진행할 수 있습니다.', 1);

-- 앱 공지사항 초기 데이터
INSERT INTO public.announcements (title, content, is_important, target_user_type) VALUES
('에뷰리띵 앱 출시!', '에뷰리띵 앱이 정식 출시되었습니다. 다양한 혜택을 확인해보세요!', true, ARRAY['user'::user_role]);

-- 정산 스케줄 초기 데이터
INSERT INTO public.settlement_schedules (
    schedule_name, settlement_period, schedule_day, schedule_time, 
    auto_approve, notification_emails, created_by
) VALUES 
('주간 정산 (목요일)', 'weekly'::settlement_period, 4, '15:00', 
 false, ARRAY['finance@ebeautything.com', 'admin@ebeautything.com'], 
 '00000000-0000-0000-0000-000000000001'::UUID),
('월간 정산 (매월 5일)', 'monthly'::settlement_period, 5, '14:00',
 false, ARRAY['finance@ebeautything.com'], 
 '00000000-0000-0000-0000-000000000001'::UUID);

-- =============================================
-- 주요 조회용 뷰들 (VIEWS FOR COMMON QUERIES)
-- =============================================

-- 사용자 포인트 요약 뷰
-- 포인트 관리 화면에서 사용할 통합 포인트 정보
CREATE VIEW user_point_summary AS
SELECT 
    u.id as user_id,
    u.name,
    u.total_points,
    u.available_points,
    COALESCE(pending.pending_points, 0) as pending_points, -- 7일 대기 중인 포인트
    COALESCE(recent.points_this_month, 0) as points_this_month -- 이번 달 적립 포인트
FROM public.users u
LEFT JOIN (
    SELECT 
        user_id,
        SUM(amount) as pending_points
    FROM public.point_transactions 
    WHERE status = 'pending'
    GROUP BY user_id
) pending ON u.id = pending.user_id
LEFT JOIN (
    SELECT 
        user_id,
        SUM(amount) as points_this_month
    FROM public.point_transactions 
    WHERE status = 'available'
    AND amount > 0
    AND created_at >= date_trunc('month', NOW())
    GROUP BY user_id
) recent ON u.id = recent.user_id;

-- 샵 성과 요약 뷰
-- 웹 관리자 대시보드의 샵 통계용
CREATE VIEW shop_performance_summary AS
SELECT 
    s.id as shop_id,
    s.name,
    s.shop_status,
    s.shop_type,
    s.total_bookings,
    COALESCE(recent.bookings_this_month, 0) as bookings_this_month, -- 이번 달 예약 수
    COALESCE(revenue.total_revenue, 0) as total_revenue -- 총 매출액
FROM public.shops s
LEFT JOIN (
    SELECT 
        shop_id,
        COUNT(*) as bookings_this_month
    FROM public.reservations
    WHERE status IN ('confirmed', 'completed')
    AND created_at >= date_trunc('month', NOW())
    GROUP BY shop_id
) recent ON s.id = recent.shop_id
LEFT JOIN (
    SELECT 
        r.shop_id,
        SUM(r.total_amount) as total_revenue
    FROM public.reservations r
    WHERE r.status = 'completed'
    GROUP BY r.shop_id
) revenue ON s.id = revenue.shop_id;

-- =============================================
-- 웹 관리자 대시보드용 뷰들 (ADMIN VIEWS FOR WEB DASHBOARD)
-- =============================================

-- 관리자용 사용자 요약 뷰
-- 웹 관리자의 사용자 관리 화면용
CREATE VIEW admin_users_summary AS
SELECT 
    id,
    name,
    email,
    phone_number,
    user_status,
    user_role,
    is_influencer,
    total_points,
    total_referrals,
    created_at
FROM public.users
ORDER BY created_at DESC;

-- 관리자용 샵 요약 뷰  
-- 웹 관리자의 샵 관리 화면용
CREATE VIEW admin_shops_summary AS
SELECT 
    s.id,
    s.name,
    s.shop_status,
    s.shop_type,
    s.main_category,
    s.total_bookings,
    u.name as owner_name,
    u.email as owner_email,
    s.created_at
FROM public.shops s
LEFT JOIN public.users u ON s.owner_id = u.id
ORDER BY s.created_at DESC;

-- 관리자용 예약 요약 뷰
-- 웹 관리자의 예약 현황 화면용
CREATE VIEW admin_reservations_summary AS
SELECT 
    r.id,
    r.reservation_date,
    r.reservation_time,
    r.status,
    r.total_amount,
    u.name as customer_name,
    u.phone_number as customer_phone,
    s.name as shop_name,
    r.created_at
FROM public.reservations r
JOIN public.users u ON r.user_id = u.id
JOIN public.shops s ON r.shop_id = s.id
ORDER BY r.reservation_date DESC, r.reservation_time DESC;

-- =============================================
-- 간소화된 데이터베이스 구조 완료
-- END OF SIMPLIFIED DATABASE STRUCTURE
-- ============================================= 

-- =============================================
-- 관리자용 설정 관리 뷰들 (ADMIN VIEWS FOR SETTINGS MANAGEMENT)
-- =============================================

-- 관리자용 시스템 설정 요약 뷰
CREATE VIEW admin_settings_summary AS
SELECT 
    category,
    COUNT(*) as setting_count,
    COUNT(CASE WHEN is_active THEN 1 END) as active_count,
    MAX(updated_at) as last_updated
FROM public.system_settings
GROUP BY category
ORDER BY category;

-- 간소화: business_policies 제거로 관련 뷰도 제거됨 

-- =============================================
-- 샵 관리자 시스템 (SHOP OWNER MANAGEMENT SYSTEM)
-- =============================================

-- 샵 대시보드 통계 뷰 (샵 사장용)
-- 샵 사장이 본인 샵의 성과를 볼 수 있는 실시간 통계
CREATE VIEW shop_owner_dashboard AS
SELECT 
    s.id as shop_id,
    s.name as shop_name,
    s.owner_id,
    -- 이번 달 통계
    COALESCE(current_month.total_bookings, 0) as this_month_bookings,
    COALESCE(current_month.completed_bookings, 0) as this_month_completed,
    COALESCE(current_month.total_revenue, 0) as this_month_revenue,
    COALESCE(current_month.commission_amount, 0) as this_month_commission,
    -- 지난달 통계 (비교용)
    COALESCE(last_month.total_bookings, 0) as last_month_bookings,
    COALESCE(last_month.total_revenue, 0) as last_month_revenue,
    -- 전체 통계
    COALESCE(all_time.total_bookings, 0) as total_bookings,
    COALESCE(all_time.total_revenue, 0) as total_revenue,
    -- 대기 중인 예약
    COALESCE(pending.pending_count, 0) as pending_reservations,
    -- 최근 정산 정보
    latest_settlement.settlement_amount as last_settlement_amount,
    latest_settlement.settled_at as last_settlement_date
FROM public.shops s
-- 이번 달 통계
LEFT JOIN (
    SELECT 
        shop_id,
        COUNT(*) as total_bookings,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_bookings,
        SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as total_revenue,
        SUM(CASE WHEN status = 'completed' THEN total_amount * calculate_commission_rate(shop_id) / 100 ELSE 0 END) as commission_amount
    FROM public.reservations
    WHERE DATE_TRUNC('month', reservation_date) = DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY shop_id
) current_month ON s.id = current_month.shop_id
-- 지난달 통계
LEFT JOIN (
    SELECT 
        shop_id,
        COUNT(*) as total_bookings,
        SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as total_revenue
    FROM public.reservations
    WHERE DATE_TRUNC('month', reservation_date) = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
    GROUP BY shop_id
) last_month ON s.id = last_month.shop_id
-- 전체 통계
LEFT JOIN (
    SELECT 
        shop_id,
        COUNT(*) as total_bookings,
        SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as total_revenue
    FROM public.reservations
    GROUP BY shop_id
) all_time ON s.id = all_time.shop_id
-- 대기 중인 예약
LEFT JOIN (
    SELECT 
        shop_id,
        COUNT(*) as pending_count
    FROM public.reservations
    WHERE status = 'requested'
    GROUP BY shop_id
) pending ON s.id = pending.shop_id
-- 최근 정산 정보
LEFT JOIN (
    SELECT DISTINCT ON (shop_id)
        shop_id,
        net_settlement_amount as settlement_amount,
        settled_at
    FROM public.shop_settlements
    WHERE settlement_status = 'completed'
    ORDER BY shop_id, settled_at DESC
) latest_settlement ON s.id = latest_settlement.shop_id;

-- =============================================
-- 샵 관리자 권한 시스템 (RLS POLICIES FOR SHOP OWNERS)
-- =============================================

-- 정산 관련 테이블들에 RLS 활성화
ALTER TABLE public.shop_settlement_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlement_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlement_schedules ENABLE ROW LEVEL SECURITY;

-- 샵 사장은 본인 샵의 정산 설정만 조회/수정 가능
CREATE POLICY "Shop owners can manage own settlement configs" ON public.shop_settlement_configs
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.shops 
            WHERE shops.id = shop_settlement_configs.shop_id 
            AND shops.owner_id = auth.uid()
        )
    );

-- 샵 사장은 본인 샵의 정산 내역만 조회 가능 (수정 불가)
CREATE POLICY "Shop owners can read own settlement history" ON public.shop_settlements
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.shops 
            WHERE shops.id = shop_settlements.shop_id 
            AND shops.owner_id = auth.uid()
        )
    );

-- 샵 사장은 본인 샵의 송금 상태만 조회 가능
CREATE POLICY "Shop owners can read own transfer status" ON public.settlement_transfers
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.shop_settlements ss
            JOIN public.shops s ON ss.shop_id = s.id
            WHERE ss.id = settlement_transfers.settlement_id
            AND s.owner_id = auth.uid()
        )
    );

-- 관리자만 정산 스케줄 관리 가능
CREATE POLICY "Only admins can manage settlement schedules" ON public.settlement_schedules
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

-- 샵 서비스 관리 정책 강화 (샵 사장이 본인 샵 서비스만 관리)
CREATE POLICY "Shop owners can manage own services" ON public.shop_services
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.shops 
            WHERE shops.id = shop_services.shop_id 
            AND shops.owner_id = auth.uid()
        )
    );

-- 샵 이미지 관리 정책
CREATE POLICY "Shop owners can manage own shop images" ON public.shop_images
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.shops 
            WHERE shops.id = shop_images.shop_id 
            AND shops.owner_id = auth.uid()
        )
    );

-- 서비스 이미지 관리 정책
CREATE POLICY "Shop owners can manage own service images" ON public.service_images
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.shop_services ss
            JOIN public.shops s ON ss.shop_id = s.id
            WHERE ss.id = service_images.service_id
            AND s.owner_id = auth.uid()
        )
    );

-- =============================================
-- 완전한 정산 프로세스 함수들 (COMPLETE SETTLEMENT PROCESS)
-- =============================================

-- 정산 승인 함수 (관리자용)
-- 관리자가 정산을 승인하고 송금 대기 상태로 변경
CREATE OR REPLACE FUNCTION approve_settlement(
    settlement_uuid UUID,
    admin_uuid UUID,
    approval_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    settlement_record RECORD;
    transfer_id UUID;
BEGIN
    -- 정산 정보 조회
    SELECT * INTO settlement_record 
    FROM public.shop_settlements 
    WHERE id = settlement_uuid AND settlement_status = 'pending';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION '승인 가능한 정산 건을 찾을 수 없습니다.';
    END IF;
    
    -- 정산 상태를 승인됨으로 변경
    UPDATE public.shop_settlements 
    SET settlement_status = 'completed'::settlement_status,
        updated_at = NOW()
    WHERE id = settlement_uuid;
    
    -- 송금 처리 레코드 생성
    INSERT INTO public.settlement_transfers (
        settlement_id,
        transfer_status,
        approved_by,
        approved_at,
        transfer_amount,
        admin_notes
    ) VALUES (
        settlement_uuid,
        'approved',
        admin_uuid,
        NOW(),
        settlement_record.net_settlement_amount,
        approval_notes
    ) RETURNING id INTO transfer_id;
    
    -- 간소화된 로그 기록
    INSERT INTO public.settlement_logs (
        settlement_id,
        action,
        performed_by,
        notes
    ) VALUES (
        settlement_uuid,
        'approved',
        admin_uuid,
        approval_notes
    );
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 송금 요청 함수
-- 실제 은행 송금이나 토스 송금을 요청하는 함수
CREATE OR REPLACE FUNCTION request_transfer(
    settlement_uuid UUID,
    admin_uuid UUID,
    transfer_method_param VARCHAR(50) DEFAULT 'bank_transfer'
)
RETURNS BOOLEAN AS $$
DECLARE
    transfer_record RECORD;
BEGIN
    -- 송금 정보 및 샵 설정 조회
    SELECT 
        st.*,
        ssc.bank_name,
        ssc.bank_account,
        ssc.account_holder
    INTO transfer_record
    FROM public.settlement_transfers st
    JOIN public.shop_settlements ss ON st.settlement_id = ss.id
    JOIN public.shop_settlement_configs ssc ON ss.shop_id = ssc.shop_id
    WHERE st.settlement_id = settlement_uuid 
    AND st.transfer_status = 'approved';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION '송금 요청 가능한 정산 건을 찾을 수 없습니다.';
    END IF;
    
    -- 송금 상태 업데이트
    UPDATE public.settlement_transfers
    SET transfer_status = 'transfer_requested',
        transfer_method = transfer_method_param,
        bank_name = transfer_record.bank_name,
        account_number = transfer_record.bank_account,
        account_holder = transfer_record.account_holder,
        transfer_requested_at = NOW(),
        updated_at = NOW()
    WHERE settlement_id = settlement_uuid;
    
    -- 간소화된 로그 기록
    INSERT INTO public.settlement_logs (
        settlement_id,
        action,
        performed_by,
        notes
    ) VALUES (
        settlement_uuid,
        'transfer_requested',
        admin_uuid,
        '송금 요청: ' || transfer_method_param || ' - ' || transfer_record.account_holder
    );
    
    -- 여기서 실제 외부 송금 API 호출
    -- 예: 토스페이먼츠, 은행 API 등
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 송금 완료 처리 함수
-- 외부 송금 서비스에서 송금 완료 콜백을 받았을 때 호출
CREATE OR REPLACE FUNCTION complete_transfer(
    settlement_uuid UUID,
    external_transfer_id_param VARCHAR(255),
    actual_transfer_amount INTEGER DEFAULT NULL,
    transfer_fee_param INTEGER DEFAULT 0
)
RETURNS BOOLEAN AS $$
BEGIN
    -- 송금 완료 상태로 업데이트
    UPDATE public.settlement_transfers
    SET transfer_status = 'transfer_completed',
        external_transfer_id = external_transfer_id_param,
        transfer_completed_at = NOW(),
        transfer_fee = transfer_fee_param,
        updated_at = NOW()
    WHERE settlement_id = settlement_uuid;
    
    -- 정산 상태를 완료로 변경
    UPDATE public.shop_settlements
    SET settlement_status = 'completed'::settlement_status,
        settled_at = NOW(),
        updated_at = NOW()
    WHERE id = settlement_uuid;
    
    -- 간소화된 로그 기록
    INSERT INTO public.settlement_logs (
        settlement_id,
        action,
        performed_by,
        notes
    ) VALUES (
        settlement_uuid,
        'completed',
        NULL, -- 시스템 자동 처리
        '송금 완료: ' || external_transfer_id_param || ' (수수료: ' || transfer_fee_param || '원)'
    );
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 정산 프로세스 상태 조회 함수
-- 샵 사장이 본인 정산 상태를 조회할 수 있는 함수
CREATE OR REPLACE FUNCTION get_settlement_status(shop_uuid UUID)
RETURNS TABLE(
    settlement_id UUID,
    period_start DATE,
    period_end DATE,
    gross_revenue INTEGER,
    commission_amount INTEGER,
    net_settlement INTEGER,
    settlement_status settlement_status,
    transfer_status VARCHAR(50),
    expected_transfer_date DATE,
    completed_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ss.id as settlement_id,
        ss.period_start_date,
        ss.period_end_date,
        ss.gross_revenue,
        ss.commission_amount,
        ss.net_settlement_amount,
        ss.settlement_status,
        COALESCE(st.transfer_status, 'not_started'::VARCHAR(50)) as transfer_status,
        -- 예상 송금일 계산 (승인 후 3영업일)
        CASE 
            WHEN st.approved_at IS NOT NULL 
            THEN (st.approved_at::DATE + INTERVAL '3 days')::DATE
            ELSE NULL
        END as expected_transfer_date,
        ss.settled_at as completed_at
    FROM public.shop_settlements ss
    LEFT JOIN public.settlement_transfers st ON ss.id = st.settlement_id
    WHERE ss.shop_id = shop_uuid
    ORDER BY ss.period_start_date DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 정산 스케줄 실행 함수
-- 크론 작업에서 호출하여 정기적으로 정산 배치 생성
CREATE OR REPLACE FUNCTION execute_scheduled_settlements()
RETURNS INTEGER AS $$
DECLARE
    schedule_record RECORD;
    batch_count INTEGER := 0;
    start_date DATE;
    end_date DATE;
BEGIN
    -- 활성화된 정산 스케줄들을 순회
    FOR schedule_record IN 
        SELECT * FROM public.settlement_schedules 
        WHERE is_active = TRUE
    LOOP
        -- 정산 기간 계산
        CASE schedule_record.settlement_period
            WHEN 'weekly' THEN
                start_date := DATE_TRUNC('week', CURRENT_DATE - INTERVAL '1 week')::DATE;
                end_date := (start_date + INTERVAL '6 days')::DATE;
            WHEN 'bi_weekly' THEN
                start_date := DATE_TRUNC('week', CURRENT_DATE - INTERVAL '2 weeks')::DATE;
                end_date := (start_date + INTERVAL '13 days')::DATE;
            WHEN 'monthly' THEN
                start_date := DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')::DATE;
                end_date := (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 day')::DATE;
        END CASE;
        
        -- 정산 배치 생성
        PERFORM create_settlement_batch(
            schedule_record.settlement_period,
            start_date,
            end_date
        );
        
        batch_count := batch_count + 1;
    END LOOP;
    
    RETURN batch_count;
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- 샵 사장 온보딩 및 관리 시스템 (SHOP OWNER ONBOARDING & MANAGEMENT)
-- =============================================

-- 샵 등록 신청 테이블
-- 샵 사장이 직접 신청하고 관리자가 승인하는 프로세스
CREATE TABLE public.shop_applications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    applicant_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, -- 신청자
    shop_name VARCHAR(255) NOT NULL, -- 신청할 샵명
    business_license_number VARCHAR(50) NOT NULL, -- 사업자등록번호
    business_license_image_url TEXT, -- 사업자등록증 이미지
    shop_address TEXT NOT NULL, -- 샵 주소
    detailed_address TEXT, -- 상세 주소
    phone_number VARCHAR(20) NOT NULL, -- 샵 전화번호
    main_category service_category NOT NULL, -- 주 서비스 카테고리
    sub_categories service_category[], -- 부가 서비스들
    description TEXT, -- 샵 소개
    application_status VARCHAR(50) DEFAULT 'pending', -- 신청 상태 ('pending', 'approved', 'rejected')
    rejection_reason TEXT, -- 거절 사유
    reviewed_by UUID REFERENCES public.users(id), -- 심사한 관리자
    reviewed_at TIMESTAMPTZ, -- 심사 완료 시간
    approved_shop_id UUID REFERENCES public.shops(id), -- 승인된 샵 ID
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 샵 운영 시간 관리 테이블 (더 구체적인 운영시간 관리)
CREATE TABLE public.shop_operating_hours (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL, -- 0=일요일, 1=월요일, ..., 6=토요일
    is_open BOOLEAN DEFAULT TRUE, -- 해당 요일 영업 여부
    open_time TIME, -- 영업 시작 시간
    close_time TIME, -- 영업 종료 시간
    break_start_time TIME, -- 휴게 시작 시간 (선택)
    break_end_time TIME, -- 휴게 종료 시간 (선택)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(shop_id, day_of_week)
);

-- 예약 승인/거부 로그 테이블
CREATE TABLE public.reservation_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reservation_id UUID NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL, -- 'confirmed', 'cancelled_by_shop', 'modified'
    performed_by UUID REFERENCES public.users(id), -- 작업한 샵 사장
    reason TEXT, -- 승인/거부 사유
    previous_status reservation_status, -- 이전 상태
    new_status reservation_status, -- 새로운 상태
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 샵 사장 알림 설정 테이블
CREATE TABLE public.shop_notification_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    new_reservation_notification BOOLEAN DEFAULT TRUE, -- 신규 예약 알림
    cancellation_notification BOOLEAN DEFAULT TRUE, -- 취소 알림
    review_notification BOOLEAN DEFAULT TRUE, -- 리뷰 알림 (향후)
    settlement_notification BOOLEAN DEFAULT TRUE, -- 정산 알림
    email_notifications BOOLEAN DEFAULT TRUE, -- 이메일 알림
    sms_notifications BOOLEAN DEFAULT FALSE, -- SMS 알림 (향후)
    notification_hours_start TIME DEFAULT '09:00', -- 알림 받을 시작 시간
    notification_hours_end TIME DEFAULT '22:00', -- 알림 받을 종료 시간
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(shop_id)
);

-- =============================================
-- 샵 사장 관리 기능 함수들 (SHOP OWNER MANAGEMENT FUNCTIONS)
-- =============================================

-- 샵 등록 신청 함수
CREATE OR REPLACE FUNCTION apply_for_shop(
    applicant_uuid UUID,
    shop_name_param VARCHAR(255),
    business_license_param VARCHAR(50),
    address_param TEXT,
    phone_param VARCHAR(20),
    main_category_param service_category,
    description_param TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    application_id UUID;
BEGIN
    -- 이미 승인된 샵이 있는지 확인
    IF EXISTS (
        SELECT 1 FROM public.shops 
        WHERE owner_id = applicant_uuid 
        AND shop_status IN ('active', 'pending_approval')
    ) THEN
        RAISE EXCEPTION '이미 등록된 샵이 있습니다.';
    END IF;
    
    -- 신청서 생성
    INSERT INTO public.shop_applications (
        applicant_id,
        shop_name,
        business_license_number,
        shop_address,
        phone_number,
        main_category,
        description,
        application_status
    ) VALUES (
        applicant_uuid,
        shop_name_param,
        business_license_param,
        address_param,
        phone_param,
        main_category_param,
        description_param,
        'pending'
    ) RETURNING id INTO application_id;
    
    RETURN application_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 샵 등록 승인 함수 (관리자용)
CREATE OR REPLACE FUNCTION approve_shop_application(
    application_uuid UUID,
    admin_uuid UUID
)
RETURNS UUID AS $$
DECLARE
    application_record RECORD;
    new_shop_id UUID;
    i INTEGER;
BEGIN
    -- 신청서 정보 조회
    SELECT * INTO application_record 
    FROM public.shop_applications 
    WHERE id = application_uuid AND application_status = 'pending';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION '승인 가능한 신청서를 찾을 수 없습니다.';
    END IF;
    
    -- 샵 생성
    INSERT INTO public.shops (
        owner_id,
        name,
        address,
        phone_number,
        main_category,
        sub_categories,
        description,
        business_license_number,
        shop_status,
        verification_status
    ) VALUES (
        application_record.applicant_id,
        application_record.shop_name,
        application_record.shop_address,
        application_record.phone_number,
        application_record.main_category,
        application_record.sub_categories,
        application_record.description,
        application_record.business_license_number,
        'active',
        'verified'
    ) RETURNING id INTO new_shop_id;
    
    -- 사용자 역할을 shop_owner로 변경
    UPDATE public.users 
    SET user_role = 'shop_owner'::user_role,
        updated_at = NOW()
    WHERE id = application_record.applicant_id;
    
    -- 기본 운영시간 설정 (월-일, 09:00-18:00)
    FOR i IN 0..6 LOOP
        INSERT INTO public.shop_operating_hours (
            shop_id, day_of_week, is_open, open_time, close_time
        ) VALUES (
            new_shop_id, i, TRUE, '09:00'::TIME, '18:00'::TIME
        );
    END LOOP;
    
    -- 기본 알림 설정 생성
    INSERT INTO public.shop_notification_settings (shop_id)
    VALUES (new_shop_id);
    
    -- 신청서 상태 업데이트
    UPDATE public.shop_applications 
    SET application_status = 'approved',
        reviewed_by = admin_uuid,
        reviewed_at = NOW(),
        approved_shop_id = new_shop_id,
        updated_at = NOW()
    WHERE id = application_uuid;
    
    RETURN new_shop_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 예약 승인 함수 (샵 사장용)
CREATE OR REPLACE FUNCTION confirm_reservation(
    reservation_uuid UUID,
    shop_owner_uuid UUID,
    confirmation_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    reservation_record RECORD;
BEGIN
    -- 예약 정보 및 권한 확인
    SELECT r.*, s.owner_id 
    INTO reservation_record
    FROM public.reservations r
    JOIN public.shops s ON r.shop_id = s.id
    WHERE r.id = reservation_uuid 
    AND r.status = 'requested'
    AND s.owner_id = shop_owner_uuid;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION '승인 가능한 예약을 찾을 수 없습니다.';
    END IF;
    
    -- 예약 상태를 confirmed로 변경
    UPDATE public.reservations 
    SET status = 'confirmed'::reservation_status,
        confirmed_at = NOW(),
        updated_at = NOW()
    WHERE id = reservation_uuid;
    
    -- 승인 로그 기록
    INSERT INTO public.reservation_actions (
        reservation_id,
        action,
        performed_by,
        reason,
        previous_status,
        new_status
    ) VALUES (
        reservation_uuid,
        'confirmed',
        shop_owner_uuid,
        confirmation_notes,
        'requested'::reservation_status,
        'confirmed'::reservation_status
    );
    
    -- 사용자에게 알림 발송 (여기서는 알림 테이블에 추가)
    INSERT INTO public.notifications (
        user_id,
        notification_type,
        title,
        message,
        related_id
    ) VALUES (
        reservation_record.user_id,
        'reservation_confirmed',
        '예약이 확정되었습니다',
        '예약이 샵에서 승인되었습니다. 예약 시간에 방문해 주세요.',
        reservation_uuid
    );
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 예약 거절 함수 (샵 사장용)
CREATE OR REPLACE FUNCTION cancel_reservation_by_shop(
    reservation_uuid UUID,
    shop_owner_uuid UUID,
    cancellation_reason TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    reservation_record RECORD;
BEGIN
    -- 예약 정보 및 권한 확인
    SELECT r.*, s.owner_id 
    INTO reservation_record
    FROM public.reservations r
    JOIN public.shops s ON r.shop_id = s.id
    WHERE r.id = reservation_uuid 
    AND r.status IN ('requested', 'confirmed')
    AND s.owner_id = shop_owner_uuid;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION '취소 가능한 예약을 찾을 수 없습니다.';
    END IF;
    
    -- 예약 상태를 cancelled_by_shop으로 변경
    UPDATE public.reservations 
    SET status = 'cancelled_by_shop'::reservation_status,
        cancellation_reason = cancellation_reason,
        cancelled_at = NOW(),
        updated_at = NOW()
    WHERE id = reservation_uuid;
    
    -- 취소 로그 기록
    INSERT INTO public.reservation_actions (
        reservation_id,
        action,
        performed_by,
        reason,
        previous_status,
        new_status
    ) VALUES (
        reservation_uuid,
        'cancelled_by_shop',
        shop_owner_uuid,
        cancellation_reason,
        reservation_record.status,
        'cancelled_by_shop'::reservation_status
    );
    
    -- 사용자에게 알림 발송
    INSERT INTO public.notifications (
        user_id,
        notification_type,
        title,
        message,
        related_id
    ) VALUES (
        reservation_record.user_id,
        'reservation_cancelled',
        '예약이 취소되었습니다',
        '샵 사정으로 예약이 취소되었습니다. 예약금은 환불됩니다.',
        reservation_uuid
    );
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 샵 운영시간 업데이트 함수
CREATE OR REPLACE FUNCTION update_shop_hours(
    shop_uuid UUID,
    day_of_week_param INTEGER,
    is_open_param BOOLEAN,
    open_time_param TIME DEFAULT NULL,
    close_time_param TIME DEFAULT NULL,
    break_start_param TIME DEFAULT NULL,
    break_end_param TIME DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    -- 운영시간 업데이트 (UPSERT)
    INSERT INTO public.shop_operating_hours (
        shop_id, day_of_week, is_open, open_time, close_time, 
        break_start_time, break_end_time
    ) VALUES (
        shop_uuid, day_of_week_param, is_open_param, 
        open_time_param, close_time_param, break_start_param, break_end_param
    )
    ON CONFLICT (shop_id, day_of_week) 
    DO UPDATE SET
        is_open = EXCLUDED.is_open,
        open_time = EXCLUDED.open_time,
        close_time = EXCLUDED.close_time,
        break_start_time = EXCLUDED.break_start_time,
        break_end_time = EXCLUDED.break_end_time,
        updated_at = NOW();
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 샵 사장 권한 정책 추가 (ADDITIONAL RLS POLICIES)
-- =============================================

-- 샵 등록 신청서 관련 정책
ALTER TABLE public.shop_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can create own shop applications" ON public.shop_applications
    FOR INSERT WITH CHECK (auth.uid() = applicant_id);

CREATE POLICY "Users can read own shop applications" ON public.shop_applications
    FOR SELECT USING (auth.uid() = applicant_id);

CREATE POLICY "Admins can read all shop applications" ON public.shop_applications
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

-- 샵 운영시간 관련 정책
ALTER TABLE public.shop_operating_hours ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Shop owners can manage own operating hours" ON public.shop_operating_hours
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.shops 
            WHERE shops.id = shop_operating_hours.shop_id 
            AND shops.owner_id = auth.uid()
        )
    );

-- 예약 승인 로그 관련 정책
ALTER TABLE public.reservation_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Shop owners can read own reservation actions" ON public.reservation_actions
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.reservations r
            JOIN public.shops s ON r.shop_id = s.id
            WHERE r.id = reservation_actions.reservation_id
            AND s.owner_id = auth.uid()
        )
    );

-- =============================================
-- 샵 사장 대시보드 향상된 뷰 (ENHANCED SHOP OWNER VIEWS)
-- =============================================

-- 샵 사장용 오늘 예약 현황 뷰
CREATE VIEW shop_today_reservations AS
SELECT 
    r.id,
    r.reservation_time,
    r.status,
    r.total_amount,
    r.special_requests,
    u.name as customer_name,
    u.phone_number as customer_phone,
    s.id as shop_id,
    s.owner_id,
    -- 서비스 정보
    ARRAY_AGG(ss.name) as service_names
FROM public.reservations r
JOIN public.users u ON r.user_id = u.id
JOIN public.shops s ON r.shop_id = s.id
JOIN public.reservation_services rs ON r.id = rs.reservation_id
JOIN public.shop_services ss ON rs.service_id = ss.id
WHERE r.reservation_date = CURRENT_DATE
GROUP BY r.id, r.reservation_time, r.status, r.total_amount, 
         r.special_requests, u.name, u.phone_number, s.id, s.owner_id
ORDER BY r.reservation_time;

-- 샵 사장용 운영시간 뷰
CREATE VIEW shop_weekly_hours AS
SELECT 
    soh.shop_id,
    soh.day_of_week,
    CASE soh.day_of_week
        WHEN 0 THEN '일요일'
        WHEN 1 THEN '월요일' 
        WHEN 2 THEN '화요일'
        WHEN 3 THEN '수요일'
        WHEN 4 THEN '목요일'
        WHEN 5 THEN '금요일'
        WHEN 6 THEN '토요일'
    END as day_name,
    soh.is_open,
    soh.open_time,
    soh.close_time,
    soh.break_start_time,
    soh.break_end_time
FROM public.shop_operating_hours soh
ORDER BY soh.shop_id, soh.day_of_week;

-- =============================================
-- 샵 사장 트리거 추가 (SHOP OWNER TRIGGERS)
-- =============================================

CREATE TRIGGER update_shop_applications_updated_at 
    BEFORE UPDATE ON public.shop_applications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_shop_operating_hours_updated_at 
    BEFORE UPDATE ON public.shop_operating_hours
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_shop_notification_settings_updated_at 
    BEFORE UPDATE ON public.shop_notification_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================
-- 누락된 관리자 권한 정책들 추가 (MISSING ADMIN POLICIES)
-- =============================================

-- 플랫폼 관리자는 모든 사용자 데이터 조회/수정 가능
CREATE POLICY "Admins can read all users" ON public.users
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

CREATE POLICY "Admins can update all users" ON public.users
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

-- 플랫폼 관리자는 모든 샵 데이터 조회/수정 가능
CREATE POLICY "Admins can read all shops" ON public.shops
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

CREATE POLICY "Admins can update all shops" ON public.shops
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

-- 플랫폼 관리자는 모든 예약 데이터 조회/수정 가능
CREATE POLICY "Admins can read all reservations" ON public.reservations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

CREATE POLICY "Admins can update all reservations" ON public.reservations
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

-- 샥 관리자는 본인 샵 예약 승인/거부 가능
CREATE POLICY "Shop owners can update shop reservations" ON public.reservations
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.shops 
            WHERE shops.id = reservations.shop_id 
            AND shops.owner_id = auth.uid()
        )
    );

-- 플랫폼 관리자는 모든 결제 데이터 조회 가능
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own payments" ON public.payments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.reservations 
            WHERE reservations.id = payments.reservation_id 
            AND reservations.user_id = auth.uid()
        )
    );

CREATE POLICY "Shop owners can read shop payments" ON public.payments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.reservations r
            JOIN public.shops s ON r.shop_id = s.id
            WHERE r.id = payments.reservation_id 
            AND s.owner_id = auth.uid()
        )
    );

CREATE POLICY "Admins can read all payments" ON public.payments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

-- 플랫폼 관리자는 모든 포인트 거래 조회/수정 가능
CREATE POLICY "Admins can read all point transactions" ON public.point_transactions
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

CREATE POLICY "Admins can update point transactions" ON public.point_transactions
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

-- 플랫폼 관리자는 시스템 설정 관리 가능
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_category_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage system settings" ON public.system_settings
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

CREATE POLICY "Admins can manage service category configs" ON public.service_category_configs
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

CREATE POLICY "Admins can manage app configs" ON public.app_configs
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

CREATE POLICY "Admins can manage promotions" ON public.promotions
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

-- 일반 사용자는 활성 프로모션만 조회 가능
CREATE POLICY "Users can read active promotions" ON public.promotions
    FOR SELECT USING (
        is_active = TRUE 
        AND start_date <= NOW() 
        AND (end_date IS NULL OR end_date >= NOW())
    );

-- 플랫폼 관리자는 모든 정산 데이터 조회/수정 가능
CREATE POLICY "Admins can manage all settlements" ON public.shop_settlements
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

CREATE POLICY "Admins can manage settlement transfers" ON public.settlement_transfers
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );

-- 플랫폼 관리자는 샵 신청서 수정 가능 (승인/거절)
CREATE POLICY "Admins can update shop applications" ON public.shop_applications
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.users 
            WHERE users.id = auth.uid() 
            AND users.user_role = 'admin'
        )
    );