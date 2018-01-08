module actuator_line_controller

     use decomp_2d, only: mytype, nrank
     
implicit none
! Define some parameters
real(mytype), parameter :: OnePlusEps= 1.0 + EPSILON(OnePlusEps)       ! The number slighty greater than unity in single precision.
real(mytype), parameter :: R2D   =  57.295780   ! Factor to convert radians to degrees.
real(mytype), parameter :: RPS2RPM= 9.5492966   ! Factor to convert radians per second to revolutions per minute.

type ControllerType
! Input parameters
real(mytype) :: CornerFreq    ! Corner frequency (-3dB point) in the recursive, single-pole, 
real(mytype) :: PC_DT         ! 0.00125 or JASON:THIS CHANGED FOR ITI BARGE: 0.0001 ! Communication interval for pitch  controller, sec.
real(mytype) :: PC_KI         ! Integral gain for pitch controller at rated pitch (zero), (-).
real(mytype) :: PC_KK         ! Pitch angle were the derivative of the aerodynamic power 
real(mytype) :: PC_KP         ! Proportional gain for pitch controller at rated pitch (zero), sec.
real(mytype) :: PC_MaxPit     ! Maximum pitch setting in pitch controller, rad.
real(mytype) :: PC_MaxRat     ! Maximum pitch  rate (in absolute value) in pitch  controller, rad/s.
real(mytype) :: PC_MinPit     ! Minimum pitch setting in pitch controller, rad.
real(mytype) :: PC_RefSpd     ! Desired (reference) HSS speed for pitch controller, rad/s.
real(mytype) :: VS_CtInSp     ! Transitional generator speed (HSS side) between regions 1 and 1 1/2, rad/s.
real(mytype) :: VS_DT         ! JASON:THIS CHANGED FOR ITI BARGE:0.0001 !Communication interval for torque controller, sec.
real(mytype) :: VS_MaxRat     ! Maximum torque rate (in absolute value) in torque controller, N-m/s.
real(mytype) :: VS_MaxTq      ! Maximum generator torque in Region 3 (HSS side), N-m. -- chosen to be 10% above VS_RtTq = 43.09355kNm
real(mytype) :: VS_Rgn2K      ! Generator torque constant in Region 2 (HSS side), N-m/(rad/s)^2.
real(mytype) :: VS_Rgn2Sp     ! Transitional generator speed (HSS side) between regions 1 1/2 and 2, rad/s.
real(mytype) :: VS_Rgn3MP     ! Minimum pitch angle at which the torque is computed as if we are in region 3 regardless of the generator speed, rad. -- chosen to be 1.0 degree above PC_MinPit
real(mytype) :: VS_RtGnSp     ! Rated generator speed (HSS side), rad/s. -- chosen to be 99% of PC_RefSpd
real(mytype) :: VS_RtPwr      ! Rated generator generator power in Region 3, Watts. 
real(mytype) :: VS_SlPc       ! Rated generator slip percentage in Region 2 1/2, %.
real(mytype) :: GearBoxRatio  ! Gear Box ratio (usually taken 97:1)
real(mytype) :: IGenerator    ! Moment of inertia for the generator

! Local Variables:
real(mytype) :: Alpha           ! Current coefficient in the recursive, single-pole, low-pass filter, (-).
real(mytype) :: BlPitch(3)      ! Current values of the blade pitch angles, rad.
real(mytype) :: ElapTime        ! Elapsed time since the last call to the controller, sec.
real(mytype) :: GenSpeed        ! Current  HSS (generator) speed, rad/s.
real(mytype) :: GenSpeedF       ! Filtered HSS (generator) speed, rad/s.
real(mytype) :: GenTrq          ! Electrical generator torque, N-m.
real(mytype) :: GK              ! Current value of the gain correction factor, used in the gain scheduling law of the pitch controller, (-).
real(mytype) :: HorWindV        ! Horizontal hub-heigh wind speed, m/s.
real(mytype) :: IntSpdErr       ! Current integral of speed error w.r.t. time, rad.
real(mytype) :: LastGenTrq      ! Commanded electrical generator torque the last time the controller was called, N-m.
real(mytype) :: LastTime        ! Last time this contoller was called, sec.
real(mytype) :: LastTimePC      ! Last time the pitch  controller was called, sec.
real(mytype) :: LastTimeVS      ! Last time the torque controller was called, sec.
real(mytype) :: PitCom(3)       ! Commanded pitch of each blade the last time the controller was called, rad.
real(mytype) :: PitComI         ! Integral term of command pitch, rad.
real(mytype) :: PitComP         ! Proportional term of command pitch, rad.
real(mytype) :: PitComT         ! Total command pitch based on the sum of the proportional and integral terms, rad.
real(mytype) :: PitRate(3)      ! Pitch rates of each blade based on the current pitch angles and current pitch command, rad/s.
real(mytype) :: SpdErr  	! Current speed error, rad/s.
real(mytype) :: Time    	! Current simulation time, sec.
real(mytype) :: TrqRate 	! Torque rate based on the current and last torque commands, N-m/s.
real(mytype) :: VS_Slope15      ! Torque/speed slope of region 1 1/2 cut-in torque ramp , N-m/(rad/s).
real(mytype) :: VS_Slope25      ! Torque/speed slope of region 2 1/2 induction generator, N-m/(rad/s).
real(mytype) :: VS_SySp         ! Synchronous speed of region 2 1/2 induction generator, rad/s.
real(mytype) :: VS_TrGnSp       ! Transitional generator speed (HSS side) between regions 2 and 2 1/2, rad/s.
integer :: iStatus              ! A status flag set by the simulation as follows: 0 if this is the first call, 
				! 1 for all subsequent time steps, -1 if this is the final call at the end of the simulation.
end type ControllerType

contains

subroutine init_controller(control)
	
	implicit none
	! Read control parameters
	type(ControllerType), intent(inout) :: control
	integer :: AviFail

	control%CornerFreq = 1.570796 ! Corner frequency (-3dB point) in the recursive, single-pole, 
	control%PC_DT=0.0025	      ! 
	control%PC_KI=0.008068634     ! Integral gain for pitch controller at rated pitch (zero), (-).
	control%PC_KK=0.1099965       ! Pitch angle were the derivative of the aerodynamic power 
	control%PC_KP= 0.01882681     ! Proportional gain for pitch controller at rated pitch (zero), sec.
	control%PC_MaxPit = 1.570796  ! Maximum pitch setting in pitch controller, rad.
	control%PC_MaxRat = 0.1396263 ! Maximum pitch  rate (in absolute value) in pitch  controller, rad/s.
	control%PC_MinPit = 0.0       ! Minimum pitch setting in pitch controller, rad.
	control%PC_RefSpd = 122.9096  ! Desired (reference) HSS speed for pitch controller, rad/s. 
	control%VS_CtInSp = 70.16224  ! Transitional generator speed (HSS side) between regions 1 and 1 1/2, rad/s.
	control%VS_DT = 0.00125       ! JASON:THIS CHANGED FOR ITI BARGE:0.0001 !Communication interval for torque controller, sec.
	control%VS_MaxRat = 15000.0   ! Maximum torque rate (in absolute value) in torque controller, N-m/s.
	control%VS_MaxTq = 47402.91   ! Maximum generator torque in Region 3 (HSS side), N-m. -- chosen to be 10% above VS_RtTq = 43.09355kNm
	control%VS_Rgn2K = 2.332287   ! Generator torque constant in Region 2 (HSS side), N-m/(rad/s)^2.
	control%VS_Rgn2Sp= 91.21091   ! Transitional generator speed (HSS side) between regions 1 1/2 and 2, rad/s.
	control%VS_Rgn3MP= 0.01745329 ! Minimum pitch angle at which the torque is computed as if we are in region 3 regardless of the generator speed, rad. -- chosen to be 1.0 degree above PC_MinPit
	control%VS_RtGnSp=121.6805    ! Rated generator speed (HSS side), rad/s. -- chosen to be 99% of PC_RefSpd
	control%VS_RtPwr= 5296610.0   ! Rated generator generator power in Region 3, Watts. 
	control%VS_SlPc=10.0          ! Rated generator slip percentage in Region 2 1/2, %. -- chosen to be 5MW divided by the electrical generator efficiency of 94.4%
	control%GearBoxRatio=97.      ! Gear box ratio
	control%IGenerator=0.001      ! Moment of Inertia for the Generator

   	! Read input parameters


   	! Determine some torque control parameters not specified directly:
   	control%VS_SySp=control%VS_RtGnSp/(1.0+0.01*control%VS_SlPc)
   	control%VS_Slope15=(control%VS_Rgn2K*control%VS_Rgn2Sp*control%VS_Rgn2Sp)/(control%VS_Rgn2Sp - control%VS_CtInSp)
   	control%VS_Slope25=(control%VS_RtPwr/control%VS_RtGnSp)/(control%VS_RtGnSp-control%VS_SySp)
   	if (control%VS_Rgn2K == 0.0)  then  ! .TRUE. if the Region 2 torque is flat, and thus, the denominator in the ELSE condition is zero
   	  control%VS_TrGnSp = control%VS_SySp
   	else                          ! .TRUE. if the Region 2 torque is quadratic with speed
   	  control%VS_TrGnSp=(control%VS_Slope25-SQRT(control%VS_Slope25*(control%VS_Slope25-4.0*control%VS_Rgn2K*control%VS_SySp)))/(2.0*control%VS_Rgn2K)
   	endif

	AviFail=1
   	
	! Check validity of input parameters:
   	if (control%CornerFreq<= 0.0 )  then
   	   	aviFAIL  = -1
   	     if (nrank==0) print *,'CornerFreq must be greater than zero.'
   	endif
   	IF (control%VS_DT<= 0.0 )  THEN
   	   aviFAIL  = -1
   	   if (nrank==0)  print *, 'VS_DT must be greater than zero.'
   	ENDIF
   	IF (control%VS_CtInSp<0.0) THEN
   	   aviFAIL  = -1
   	   if (nrank==0)  print *,'VS_CtInSp must not be negative.'
   	ENDIF
   	IF (control%VS_Rgn2Sp <= control%VS_CtInSp )  THEN
   	   aviFAIL  = -1
   	   if (nrank==0) print *,'VS_Rgn2Sp must be greater than VS_CtInSp.'
   	ENDIF
   	IF (control%VS_TrGnSp <  control%VS_Rgn2Sp )  THEN
   	   aviFAIL  = -1
   	   if (nrank==0) print *,'VS_TrGnSp must not be less than VS_Rgn2Sp.'
   	ENDIF
	IF (control%VS_SlPc   <= 0.0 )  THEN
      	   aviFAIL  = -1
	   if (nrank==0) print *,'VS_SlPc must be greater than zero.'
	ENDIF

	IF (control%VS_MaxRat <= 0.0 )  THEN
	   aviFAIL  =  -1
	   if (nrank==0) print *,'VS_MaxRat must be greater than zero.'
	ENDIF
	
	IF (control%VS_RtPwr  <  0.0 )  THEN
	   aviFAIL  = -1
	   if (nrank==0) print *,'VS_RtPwr must not be negative.'
	ENDIF
	
	IF (control%VS_Rgn2K  <  0.0 )  THEN
	   aviFAIL  = -1
	   if (nrank==0) print *,'VS_Rgn2K must not be negative.'
	ENDIF
	
	IF (control%VS_Rgn2K*control%VS_RtGnSp*control%VS_RtGnSp > control%VS_RtPwr/control%VS_RtGnSp )  THEN
	   aviFAIL  = -1
	   if (nrank==0) print *,'VS_Rgn2K*VS_RtGnSp^2 must not be greater than VS_RtPwr/VS_RtGnSp.'
	ENDIF
	
	IF (control%VS_MaxTq < control%VS_RtPwr/control%VS_RtGnSp )  THEN
	   aviFAIL  = -1
	   if (nrank==0) print *,'VS_RtPwr/VS_RtGnSp must not be greater than VS_MaxTq.'
	ENDIF
	
	IF (control%PC_DT<= 0.0)  THEN
	   aviFAIL  = -1
	   if (nrank==0) print *,'PC_DT must be greater than zero.'
	ENDIF
	
	IF (control%PC_KI<= 0.0)  THEN
	   aviFAIL  = -1
	   if (nrank==0) print*,'PC_KI must be greater than zero.'
	ENDIF
	
	IF (control%PC_KK<= 0.0)  THEN
	   aviFAIL  = -1
	   if (nrank==0) print*,'PC_KK must be greater than zero.'
	ENDIF
	
	IF (control%PC_RefSpd<=0.0)  THEN
	   aviFAIL  = -1
	   if (nrank==0) print*,'PC_RefSpd must be greater than zero.'
	ENDIF
	
	IF (control%PC_MaxRat <= 0.0)  THEN
	   aviFAIL  = -1
	   if (nrank==0) print*,'PC_MaxRat must be greater than zero.'
	ENDIF
	
	IF (control%PC_MinPit >= control%PC_MaxPit)  THEN
	   aviFAIL  = -1
	   if (nrank==0) print*,'PC_MinPit must be less than PC_MaxPit.'
	ENDIF

	if (aviFail<0) stop
   	
	! Inform users that we are using this user-defined routine:
   	if(nrank==0) then
   	print *, '+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
	print *, 'Running with torque and pitch control of the NREL offshore '
   	print *, '5MW baseline wind turbine from DISCON.dll as written by J. '
   	print *, 'Jonkman of NREL/NWTC for use in the IEA Annex XXIII OC3 '   
   	print *, 'studies.'
   	print *, '+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
   	endif
	
	return

end subroutine init_controller

subroutine operate_controller(control,time,NumBl)

   	implicit none
   	type(ControllerType), intent(inout) :: control
   	real(mytype), intent(in) :: Time
        integer,intent(in) :: NumBl

   	! This Bladed-style DLL controller is used to implement a variable-speed
   	! generator-torque controller and PI collective blade pitch controller for
   	! the NREL Offshore 5MW baseline wind turbine.  This routine was written by
   	! J. Jonkman of NREL/NWTC for use in the IEA Annex XXIII OC3 studies.

	if(control%iStatus==0) then
	control%GenSpeedF=control%GenSpeed !This will ensure that generator speed filter will use the initial value of the generator speed on the first pass
	control%PitCom=control%BlPitch ! This will ensure that the variable speed controller picks the correct control region and the pitch controller pickes the correct gain on the first call
	control%GK = 1.0/(1.0 + control%PitCom(1)/control%PC_KK) ! This will ensure that the pitch angle is unchanged if the initial SpdErr is zero
	control%IntSpdErr=control%PitCom(1)/(control%GK*control%PC_KI)! This will ensure that the pitch angle is unchanged if the initial SpdErr is zero
	control%LastTime=Time ! This will ensure that generator speed filter will use the initial value of the generator speed on the first pass
	control%LastTimePC=Time-control%PC_DT  ! This will ensure that the pitch  controller is called on the first pass 
	control%LastTimeVS =Time-control%VS_DT ! This will ensure that the torque controller is called on the first pass 
	endif   	

   	IF (control%iStatus>=0)  THEN  ! .TRUE. if were want to do control
	
   	!Main control calculations:
	!========================================================================================	
	! Filter the HSS (generator) speed measurement:
	! NOTE: This is a very simple recursive, single-pole, low-pass filter with
	!       exponential smoothing.
	! Update the coefficient in the recursive formula based on the elapsed time
	!   since the last call to the controller:
	control%Alpha= EXP((control%LastTime-Time)*control%CornerFreq)
	! Apply the filter:
	control%GenSpeedF=(1.0-control%Alpha)*control%GenSpeed+control%Alpha*control%GenSpeedF
	!======================================================================================== 
	
	! Variable-speed torque control:	
	
	! Compute the elapsed time since the last call to the controller:
	control%ElapTime=Time-control%LastTimeVS
	
	! Only perform the control calculations if the elapsed time is greater than
	!   or equal to the communication interval of the torque controller:
	! NOTE: Time is scaled by OnePlusEps to ensure that the contoller is called
	!       at every time step when VS_DT = DT, even in the presence of
	!       numerical precision errors.

	IF((Time*OnePlusEps-control%LastTimeVS)>=control%VS_DT)  THEN
   	! Compute the generator torque, which depends on which region we are in:
	IF((control%GenSpeedF>=control%VS_RtGnSp).OR.(control%PitCom(1)>=control%VS_Rgn3MP)) THEN ! We are in region 3 - power is constant
         control%GenTrq = control%VS_RtPwr/control%GenSpeedF
      	ELSEIF(control%GenSpeedF<=control%VS_CtInSp)  THEN ! We are in region 1 - torque is zero
         control%GenTrq = 0.0
      	ELSEIF(control%GenSpeedF<control%VS_Rgn2Sp)  THEN  ! We are in region 1 1/2 - linear ramp in torque from zero to optimal
         control%GenTrq =control%VS_Slope15*(control%GenSpeedF-control%VS_CtInSp)
      	ELSEIF(control%GenSpeedF<control%VS_TrGnSp)  THEN  ! We are in region 2 - optimal torque is proportional to the square of the generator speed
         control%GenTrq =control%VS_Rgn2K*control%GenSpeedF*control%GenSpeedF
      	ELSE   ! We are in region 2 1/2 - simple induction generator transition region
         control%GenTrq =control%VS_Slope25*(control%GenSpeedF-control%VS_SySp)
      	ENDIF

   	! Saturate the commanded torque using the maximum torque limit:
	control%GenTrq = MIN(control%GenTrq,control%VS_MaxTq)   ! Saturate the command using the maximum torque limit
   	! Saturate the commanded torque using the torque rate limit:

      	if (control%iStatus==0) control%LastGenTrq = control%GenTrq   ! Initialize the value of LastGenTrq on the first pass only
      	
	control%TrqRate=(control%GenTrq-control%LastGenTrq)/control%ElapTime               ! Torque rate (unsaturated)
        control%TrqRate=MIN(MAX(control%TrqRate,-control%VS_MaxRat),control%VS_MaxRat)   ! Saturate the torque rate using its maximum absolute value
        control%GenTrq=control%LastGenTrq+control%TrqRate*control%ElapTime ! Saturate the command using the torque rate limit
	! Reset the values of LastTimeVS and LastGenTrq to the current values:
        control%LastTimeVS = Time
        control%LastGenTrq = control%GenTrq
        ENDIF
   	
!!=======================================================================
!
!
!   ! Pitch control:
!
!   ! Compute the elapsed time since the last call to the controller:
!
!   ElapTime = Time - LastTimePC
!
!
!   ! Only perform the control calculations if the elapsed time is greater than
!   !   or equal to the communication interval of the pitch controller:
!   ! NOTE: Time is scaled by OnePlusEps to ensure that the contoller is called
!   !       at every time step when PC_DT = DT, even in the presence of
!   !       numerical precision errors.
!
!   IF ( ( Time*OnePlusEps - LastTimePC ) >= PC_DT )  THEN
!
!
!   ! Compute the gain scheduling correction factor based on the previously
!   !   commanded pitch angle for blade 1:
!
!      GK = 1.0/( 1.0 + PitCom(1)/PC_KK )
!
!
!   ! Compute the current speed error and its integral w.r.t. time; saturate the
!   !   integral term using the pitch angle limits:
!
!      SpdErr    = GenSpeedF - PC_RefSpd                                 ! Current speed error
!      IntSpdErr = IntSpdErr + SpdErr*ElapTime                           ! Current integral of speed error w.r.t. time
!      IntSpdErr = MIN( MAX( IntSpdErr, PC_MinPit/( GK*PC_KI ) ), &
!                                       PC_MaxPit/( GK*PC_KI )      )    ! Saturate the integral term using the pitch angle limits, converted to integral speed error limits
!
!
!   ! Compute the pitch commands associated with the proportional and integral
!   !   gains:
!
!      PitComP   = GK*PC_KP*   SpdErr                                    ! Proportional term
!      PitComI   = GK*PC_KI*IntSpdErr                                    ! Integral term (saturated)
!
!
!   ! Superimpose the individual commands to get the total pitch command;
!   !   saturate the overall command using the pitch angle limits:
!
!      PitComT   = PitComP + PitComI                                     ! Overall command (unsaturated)
!      PitComT   = MIN( MAX( PitComT, PC_MinPit ), PC_MaxPit )           ! Saturate the overall command using the pitch angle limits
!
!
!   ! Saturate the overall commanded pitch using the pitch rate limit:
!   ! NOTE: Since the current pitch angle may be different for each blade
!   !       (depending on the type of actuator implemented in the structural
!   !       dynamics model), this pitch rate limit calculation and the
!   !       resulting overall pitch angle command may be different for each
!   !       blade.
!
!      DO K = 1,NumBl ! Loop through all blades
!
!         PitRate(K) = ( PitComT - BlPitch(K) )/ElapTime                 ! Pitch rate of blade K (unsaturated)
!         PitRate(K) = MIN( MAX( PitRate(K), -PC_MaxRat ), PC_MaxRat )   ! Saturate the pitch rate of blade K using its maximum absolute value
!         PitCom (K) = BlPitch(K) + PitRate(K)*ElapTime                  ! Saturate the overall command of blade K using the pitch rate limit
!
!      ENDDO          ! K - all blades
!
!
!   ! Reset the value of LastTimePC to the current value:
!
!      LastTimePC = Time
!
!
!   ! Output debugging information if requested:
!
!      IF ( PC_DbgOut )  WRITE (UnDb,FmtDat)  Time, ElapTime, HorWindV, GenSpeed*RPS2RPM, GenSpeedF*RPS2RPM,           &
!                                             100.0*SpdErr/PC_RefSpd, SpdErr, IntSpdErr, GK, PitComP*R2D, PitComI*R2D, &
!                                             PitComT*R2D, PitRate(1)*R2D, PitCom(1)*R2D
!
!
!   ENDIF
!
!
!   ! Set the pitch override to yes and command the pitch demanded from the last
!   !   call to the controller (See Appendix A of Bladed User's Guide):
!
!   avrSWAP(55) = 0.0       ! Pitch override: 0=yes
!
!   avrSWAP(42) = PitCom(1) ! Use the command angles of all blades if using individual pitch
!   avrSWAP(43) = PitCom(2) ! "
!   avrSWAP(44) = PitCom(3) ! "
!
!   avrSWAP(45) = PitCom(1) ! Use the command angle of blade 1 if using collective pitch


 	! Reset the value of LastTime to the current value:

   	control%LastTime = Time	

	endif 

	return

end subroutine operate_controller


end module actuator_line_controller